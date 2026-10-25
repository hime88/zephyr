import Foundation

// =========================================================================
// MARK: - KernelTolerance
//
// Single canonical tolerance set for all 2D CAD kernel math in Zephyr.
// Absolute semantics are preserved deliberately (this is CAD): callers
// must NOT loosen these per call site. Robustness at large coordinates
// (e.g. state-plane values ~2.4e6, where 1 ULP of Double is ~4.7e-10)
// comes from solving in a *locally shifted frame* inside the kernel
// solvers (see Intersector2D.shiftedFrame), not from scaling tolerance.
//
//   linear     — absolute distance tolerance in world units (1e-9).
//   parametric — normalized-parameter tolerance for t in [0, 1] (1e-9).
//                Chosen so that paramTol * typicalCurveLength stays well
//                under linear for drawing-scale geometry, while remaining
//                meaningful for solver convergence tests.
//   bulgeZero  — |bulge| below this is a straight line. Kept identical to
//                CADPolyline's 1e-12 threshold (CADEntity.swift) so the
//                kernel and the entity layer agree on line-vs-arc.
// =========================================================================

public enum KernelTolerance: Sendable {
    /// Absolute linear distance tolerance in world units.
    public static let linear: Double = 1e-9
    /// Normalized parametric tolerance (for t in [0, 1]).
    public static let parametric: Double = 1e-9
    /// Bulge magnitude below which a polyline segment is a straight line.
    /// Matches CADPolyline's internal 1e-12 threshold exactly.
    public static let bulgeZero: Double = 1e-12
}
