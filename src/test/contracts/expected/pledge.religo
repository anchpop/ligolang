type storage = address;

type parameter =   Donate(unit)
| Distribute(((unit => list(operation))));

let donate = 
  (((p, s): (unit, storage))): (list(operation), storage) => 
    {
      (([] : list(operation)), s)
    };

let distribute = 
  (((p, s): ((unit => list(operation)), storage)))
  :
    (list(operation), storage) => 
    {
      if(Tezos.sender
      == s) {
        (p(()), s)
      } else {
      
        (
          failwith("You're not the oracle for this distribution.")
          : (list(operation), storage))
      }
    };

let main = 
  (((p, s): (parameter, storage)))
  :
    (list(operation), storage) => 
    {
      switch(p) {
      | Donate => donate(((), s))
      | Distributemsg => distribute((msg, s))
      }
    };
