#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

// 液态玻璃的边缘折射 —— 逐行移植自 Kyant0/AndroidLiquidGlass（Apache-2.0）
// backdrop/src/commonMain/kotlin/com/kyant/backdrop/internal/Shaders.kt 的
// RoundedRectRefractionShaderString。数学照搬：圆角矩形 SDF、解析梯度、
// circleMap 圆弧位移轮廓、gradRadius = 1.5×圆角的梯度平滑。
//
// circleMap 的边缘斜率无穷大：背景在靠边缘处被急剧压缩、翻折、再展开 ——
// 这个翻折就是「厚玻璃透镜」的边缘质感，是效果的灵魂，不是要修的伪影。
// （想压住翻折就把 amount 压到带高一半以下，代价是效果退回磨砂玻璃。）
//
// 与原版只差两处，都有明确理由：
//
// 1. 位移方向取 -grad（朝内采样）。原版 +grad 朝外采样，依赖 drawBackdrop
//    捕获时外扩 padding 环的真实背景；Flutter 的 BackdropFilter 纹理正好等于
//    控件边界、外面没有内容，朝外采样会 clamp 出一条死色边。模糊层在下、
//    边缘内外背景连续，朝内采样的弯折观感与原版等价。
// 2. vibrancy（饱和 ×1.5）搬进本 shader。饱和是线性变换、模糊是线性卷积，
//    两者可交换，与原管线 vibrancy ⇒ blur ⇒ lens 等价。
//
// ⚠️ 三条来自 Flutter 引擎的硬约束，改了会静默出错：
//
// 1. 第一个 uniform 必须是 vec2，由引擎填入**输入纹理的尺寸**，不要自己
//    setFloat（只有直接当 Paint.shader 用时才自己填）。
// 2. 必须至少有一个 sampler2D，第一个由引擎绑定为滤镜输入。
// 3. OpenGLES 后端 y 轴是反的，要按 IMPELLER_TARGET_OPENGLES 翻一次，
//    否则整个玻璃上下颠倒（圆角还在，只是背景反了，很容易看漏）。
uniform vec2 uSize;      // 引擎填：纹理尺寸（物理像素）
uniform vec4 uRadii;     // 四角圆角半径 (tl, tr, br, bl)，胶囊时四值相同
uniform float uRefrH;    // 折射带宽度（从边缘往内算，物理像素）
uniform float uRefrAmt;  // 边缘处最大采样位移（物理像素），参考默认 = uRefrH
uniform float uDepth;    // 景深开关 0/1（参考的 depthEffect，默认 0）
uniform float uChroma;   // 色散开关 0/1（参考的 chromaticAberration，默认 0）

uniform sampler2D uTex;  // 滤镜输入

out vec4 fragColor;

/// 按象限取对应角的圆角半径（y 轴向下：+x -y = 右上）。
float radiusAt(vec2 p, vec4 radii) {
    if (p.x >= 0.0) {
        return p.y <= 0.0 ? radii.y : radii.z;
    }
    return p.y <= 0.0 ? radii.x : radii.w;
}

/// 圆角矩形 SDF：< 0 在内部。先按所在象限取该角的 r 再算。
float sdRoundedRect(vec2 coord, vec2 halfSize, float radius) {
    vec2 cornerCoord = abs(coord) - (halfSize - vec2(radius));
    float outside = length(max(cornerCoord, vec2(0.0))) - radius;
    float inside = min(max(cornerCoord.x, cornerCoord.y), 0.0);
    return outside + inside;
}

/// SDF 解析梯度（朝外）。平角边取轴向、圆角处取径向，转角连续。
vec2 gradSdRoundedRect(vec2 coord, vec2 halfSize, float radius) {
    vec2 cornerCoord = abs(coord) - (halfSize - vec2(radius));
    if (cornerCoord.x >= 0.0 || cornerCoord.y >= 0.0) {
        vec2 m = max(cornerCoord, vec2(0.0));
        float ml = length(m);
        vec2 dir = ml > 1e-6 ? m / ml : vec2(1.0, 0.0);
        return sign(coord) * dir;
    }
    float gradX = step(cornerCoord.y, cornerCoord.x);
    return sign(coord) * vec2(gradX, 1.0 - gradX);
}

/// 位移轮廓：x ∈ [0,1]（0 = 带内界，1 = 边缘）→ [0,1]。四分之一圆弧。
float circleMap(float x) {
    return 1.0 - sqrt(1.0 - x * x);
}

/// vibrancy()：饱和 ×1.5。
vec3 vibrancy(vec3 c) {
    float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
    return mix(vec3(luma), c, 1.5);
}

void main() {
    vec2 size = uSize;
    vec2 uv = FlutterFragCoord().xy / size;

    // 统一到纹理空间再算一切：翻转放在最前面，后面的 SDF、梯度、位移
    // 就都是同一套坐标，不必为 GLES 单独维护一份逻辑。
#ifdef IMPELLER_TARGET_OPENGLES
    uv.y = 1.0 - uv.y;
#endif

    vec2 coord = uv * size;
    vec2 halfSize = size * 0.5;
    vec2 centeredCoord = coord - halfSize;
    float radius = radiusAt(centeredCoord, uRadii);

    float sd = sdRoundedRect(centeredCoord, halfSize, radius);
    vec2 sampleUv = uv;
    vec2 dispUv = vec2(0.0);
    // 只处理靠边缘的折射带；带内界的再往内原样透出。
    if (uRefrH > 0.5 && uRefrAmt > 0.0 && -sd < uRefrH) {
        float inner = min(sd, 0.0);          // -inner ∈ [0, uRefrH]
        float d = circleMap(1.0 - -inner / uRefrH) * uRefrAmt;
        // 梯度用 1.5× 圆角半径算：把转角处的法线过渡抹宽，圆角弯折更顺。
        float gradRadius = min(radius * 1.5, min(halfSize.x, halfSize.y));
        vec2 grad = normalize(gradSdRoundedRect(centeredCoord, halfSize, gradRadius)
                              + uDepth * normalize(centeredCoord));
        sampleUv = (coord - d * grad) / size;
        // 色散（chromaticAberration）：参考 RoundedRectRefractionWithDispersion
        // 的七采样光谱分裂。位移强度沿对角坐标渐变（中心 0、对角最大）。
        // 本移植整体朝内采样（-grad），谱向随之镜像，保持与弯折方向一致。
        float dispersionIntensity =
            uChroma * ((centeredCoord.x * centeredCoord.y) / (halfSize.x * halfSize.y));
        dispUv = (d * grad * dispersionIntensity) / size;
    }

    vec4 src;
    if (uChroma > 0.5 && (dispUv.x != 0.0 || dispUv.y != 0.0)) {
        // 七采样：红→紫按 ±dispUv 梯度排布，权重照搬参考实现。
        vec4 color = vec4(0.0);
        vec4 tap;
        tap = texture(uTex, clamp(sampleUv - dispUv, vec2(0.0), vec2(1.0)));
        color.r += tap.r / 3.5;
        color.a += tap.a / 7.0;
        tap = texture(uTex, clamp(sampleUv - dispUv * (2.0 / 3.0), vec2(0.0), vec2(1.0)));
        color.r += tap.r / 3.5;
        color.g += tap.g / 7.0;
        color.a += tap.a / 7.0;
        tap = texture(uTex, clamp(sampleUv - dispUv * (1.0 / 3.0), vec2(0.0), vec2(1.0)));
        color.r += tap.r / 3.5;
        color.g += tap.g / 3.5;
        color.a += tap.a / 7.0;
        tap = texture(uTex, clamp(sampleUv, vec2(0.0), vec2(1.0)));
        color.g += tap.g / 3.5;
        color.a += tap.a / 7.0;
        tap = texture(uTex, clamp(sampleUv + dispUv * (1.0 / 3.0), vec2(0.0), vec2(1.0)));
        color.g += tap.g / 3.5;
        color.b += tap.b / 3.0;
        color.a += tap.a / 7.0;
        tap = texture(uTex, clamp(sampleUv + dispUv * (2.0 / 3.0), vec2(0.0), vec2(1.0)));
        color.b += tap.b / 3.0;
        color.a += tap.a / 7.0;
        tap = texture(uTex, clamp(sampleUv + dispUv, vec2(0.0), vec2(1.0)));
        color.r += tap.r / 7.0;
        color.b += tap.b / 3.0;
        color.a += tap.a / 7.0;
        src = color;
    } else {
        src = texture(uTex, clamp(sampleUv, vec2(0.0), vec2(1.0)));
    }
    fragColor = vec4(vibrancy(src.rgb), src.a);
}
