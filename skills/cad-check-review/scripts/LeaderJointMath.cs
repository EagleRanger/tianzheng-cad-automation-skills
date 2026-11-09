using System;

// Same signed-ray definition as check_leader_angle.py. No supplementary angle.
public static class LeaderJointMath
{
    public static double Angle(double[] anchor, double[] elbow, double[] bearing)
    {
        foreach (var p in new[] { anchor, elbow, bearing })
            if (p == null || p.Length < 2 || double.IsNaN(p[0]) || double.IsNaN(p[1]) ||
                double.IsInfinity(p[0]) || double.IsInfinity(p[1]))
                throw new ArgumentException("NONFINITE_POINT");
        double ux = anchor[0] - elbow[0], uy = anchor[1] - elbow[1];
        double vx = bearing[0] - elbow[0], vy = bearing[1] - elbow[1];
        double lu = Math.Sqrt(ux * ux + uy * uy), lv = Math.Sqrt(vx * vx + vy * vy);
        if (lu < 1e-8 || lv < 1e-8) throw new ArgumentException("ZERO_LEG");
        return Math.Acos(Math.Max(-1, Math.Min(1, (ux * vx + uy * vy) / (lu * lv)))) * 180 / Math.PI;
    }
    public static bool Accept(double angle)
    {
        return !double.IsNaN(angle) && angle >= 90 - 1e-6 && angle < 180 - 1e-6;
    }
}
