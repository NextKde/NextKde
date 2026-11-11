import QtQuick
import QtTest
import "../../shared/qml/foundation" as Foundation

TestCase {
    name: "MotionTokens"
    Foundation.MotionTokens { id: policy }

    function test_style_switch_preserves_ladder() {
        for (const material of [false, true, false]) {
            policy.isMaterial = material
            const tiers = [policy.instant, policy.fast, policy.base, policy.slow, policy.page]
            compare(tiers.map(tier => tier.duration), [100, 120, 160, 220, 300])
            for (const tier of tiers) {
                compare(tier.enterCurve, material ? Easing.OutQuart : Easing.OutCubic)
                compare(tier.exitCurve, material ? Easing.InQuart : Easing.InCubic)
            }
            compare(policy.settleCurve, material ? Easing.InOutQuart : Easing.InOutCubic)
        }
    }

    function test_reduce_motion_keeps_nominal_policy() {
        Foundation.AppTheme.reduceMotion = true
        compare(Foundation.AppTheme.motionFast, 0)
        compare(Foundation.AppTheme.motionNormal, 0)
        compare(Foundation.AppTheme.motion.fast.duration, policy.fast.duration)
        Foundation.AppTheme.reduceMotion = false
        compare(Foundation.AppTheme.motionFast, policy.fast.duration)
        compare(Foundation.AppTheme.motionNormal, policy.slow.duration)
    }
}
