// Frame-synchronised damped spring.
//
// Qt's SpringAnimation integrates at a fixed 16 ms step regardless of the
// display's refresh rate, so on a 240 Hz output it moves the property in
// ~60 Hz quanta and the motion stutters even though the compositor presents
// every frame. This integrator is advanced once per rendered frame from
// FrameAnimation.frameTime and uses the closed-form solution of a damped
// harmonic oscillator, so 60 Hz, 120 Hz and 240 Hz trace exactly the same
// curve instead of converging to it at different rates.
//
// The parameters are the continuous equivalent of the spring tuning the
// desktop reviewed earlier: Qt's (spring 3.5, damping 0.30) is about
// [18.25 rad/s, ratio 0.71] and (5.0, 0.50) is about [30 rad/s, ratio 1.33].
// Qt's units are not SI; the pairs were fitted to trajectories captured from
// SpringAnimation, which keeps the reviewed feel while removing the fixed-step
// quantisation.
//
// The closed form also stays stable when a frame is late (a dropped frame, a
// stalled render thread): a long delta simply decays towards the target
// instead of taking an Euler-sized leap past it.
export function step(value, velocity, target, deltaSeconds,
    angularFrequency, dampingRatio, epsilon) {
    const omega = Math.max(0, Number(angularFrequency) || 0);
    const zeta = Math.max(0, Number(dampingRatio) || 0);
    const settleEpsilon = Number(epsilon) > 0 ? Number(epsilon) : 1e-6;
    // A very long pause (suspend) must not move the spring further than the
    // overshoot the physics allows; the closed form decays it anyway, the cap
    // only bounds the math for pathological inputs.
    const dt = Math.min(Math.max(Number(deltaSeconds) || 0, 0), 1);
    if (!(dt > 0) || omega <= 0)
        return { value, velocity };

    const offset = value - target;
    const decay = Math.exp(-zeta * omega * dt);
    let nextOffset;
    let nextVelocity;

    if (Math.abs(zeta - 1) < 1e-4) {
        // Critically damped: x(t) = (x0 + (v0 + w x0) t) e^(-w t).
        nextOffset = (offset + (velocity + omega * offset) * dt) * decay;
        nextVelocity = (velocity - omega * dt * (velocity + omega * offset)) * decay;
    } else if (zeta < 1) {
        // Under-damped: an oscillation inside an exponential envelope.
        const dampedOmega = omega * Math.sqrt(1 - zeta * zeta);
        const cosine = Math.cos(dampedOmega * dt);
        const sine = Math.sin(dampedOmega * dt);
        const amplitudeOffset = offset;
        const amplitudeVelocity = (velocity + zeta * omega * offset) / dampedOmega;
        nextOffset = decay * (amplitudeOffset * cosine + amplitudeVelocity * sine);
        nextVelocity = decay * ((amplitudeVelocity * dampedOmega - zeta * omega * amplitudeOffset) * cosine
            - (amplitudeOffset * dampedOmega + zeta * omega * amplitudeVelocity) * sine);
    } else {
        // Over-damped: two decaying exponentials.
        const root = omega * Math.sqrt(zeta * zeta - 1);
        const slow = -zeta * omega + root;
        const fast = -zeta * omega - root;
        const slowAmplitude = (velocity - fast * offset) / (slow - fast);
        const fastAmplitude = offset - slowAmplitude;
        const slowDecay = Math.exp(slow * dt);
        const fastDecay = Math.exp(fast * dt);
        nextOffset = slowAmplitude * slowDecay + fastAmplitude * fastDecay;
        nextVelocity = slowAmplitude * slow * slowDecay + fastAmplitude * fast * fastDecay;
    }

    const nextValue = target + nextOffset;
    if (!Number.isFinite(nextValue) || !Number.isFinite(nextVelocity)) {
        // Degenerate parameters (NaN from a broken token binding) must not
        // leave the item stuck between positions.
        return { value: target, velocity: 0 };
    }
    // Qt stops as soon as the property is within epsilon of the target; the
    // velocity bound keeps a fast pass-through from settling early.
    if (Math.abs(target - nextValue) <= settleEpsilon
        && Math.abs(nextVelocity) <= settleEpsilon * Math.max(omega, 1)) {
        return { value: target, velocity: 0 };
    }
    return { value: nextValue, velocity: nextVelocity };
}
