type storage = unit;

let main = 
  (((a, s): (unit, storage))): unit => 
    
    (((f: (unit => unit))) => f(()))(((useless: unit)) => 
        unit);
