// name: expconn4.mo
// keywords:
// status: correct
// cflags:   +d=scodeInst
//
// FAILREASON: Expandable connectors not handled yet.
//

expandable connector EC
  RealInput ri;
end EC;

connector RealInput = input Real;

model M
  EC ec;
  RealInput ri;
equation
  connect(ec.ri, ri);
end M;