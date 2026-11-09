using Autodesk.AutoCAD.Runtime;

// A unique public command prevents an older, already loaded generic command
// from consuming viewport_freeze. The existing engine retains all preconditions,
// native transactions, protected-state checks, save/reopen and receipt handling.
public class ViewportFreezeDispatchV1 {
 [CommandMethod("HLCADVIEWPORTFREEZEV1",CommandFlags.Session)]
 public void Run(){new BoundCadEditsV6().Run();}
}
