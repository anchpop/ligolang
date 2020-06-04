type storage = int;

type parameter = Increment(int) | Decrement(int);

let add = (((a, b): (int, int))): int => a + b;

let sub = (((a, b): (int, int))): int => a - b;

let main = 
  (((p, storage): (parameter, storage))) => 
    {
      let storage = 
        switch(p) {
        | Increment(n) => add((storage, n))
        | Decrement(n) => sub((storage, n))
        };
      ([] : list(operation), storage)
    };
