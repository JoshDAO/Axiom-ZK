```
//   _    _       _      ___  _____  ______ _____  _      
//  | |  | |     | |    |__ \|  __ \|  ____|  __ \| |     
//  | |__| | __ _| | ___   ) | |__) | |__  | |__) | |     
//  |  __  |/ _` | |/ _ \ / /|  _  /|  __| |  ___/| |     
//  | |  | | (_| | | (_) / /_| | \ \| |____| |    | |____ 
//  |_|  |_|\__,_|_|\___/____|_|  \_\______|_|    |______|  
//

/*

    E1: Maximum
    Write a circuit which constrains the following function:

    public inputs:
    an array `arr` of length 10, each entry of which is known to be 8-bit

    public outputs:
    the maximum of the array

*/

/*

input:
{
    "arr": [10, 9, 8, 7, 34, 5, 4, 3, 2, 1, 5, 83]
}

*/

let inputs = arr.map(witness)
let maxValue = inputs[0]

for (let i = 1; i < inputs.length; i++){
    if(isLessThan(maxValue, inputs[i]).number() == 1){
        maxValue = inputs[i]
    }
}
makePublic(maxValue)

```
```
//   _    _       _      ___  _____  ______ _____  _      
//  | |  | |     | |    |__ \|  __ \|  ____|  __ \| |     
//  | |__| | __ _| | ___   ) | |__) | |__  | |__) | |     
//  |  __  |/ _` | |/ _ \ / /|  _  /|  __| |  ___/| |     
//  | |  | | (_| | | (_) / /_| | \ \| |____| |    | |____ 
//  |_|  |_|\__,_|_|\___/____|_|  \_\______|_|    |______|  
//

/*

    E2: Integer division
    Write a circuit which constrains the following function:

    public inputs:
    an non-negative integer x, which is known to be 16-bit

    public outputs:
    The non-negative integer (x / 32), where "/" represents integer division.

*/

/*

input:
{
    input: 26497
}

*/


const x = witness(input)
const maxUint16 = pow(constant(2), constant(16))

checkLessThan(x, maxUint16)

makePublic(div(x, constant(32)))


```

```
//   _    _       _      ___  _____  ______ _____  _      
//  | |  | |     | |    |__ \|  __ \|  ____|  __ \| |     
//  | |__| | __ _| | ___   ) | |__) | |__  | |__) | |     
//  |  __  |/ _` | |/ _ \ / /|  _  /|  __| |  ___/| |     
//  | |  | | (_| | | (_) / /_| | \ \| |____| |    | |____ 
//  |_|  |_|\__,_|_|\___/____|_|  \_\______|_|    |______|  
//

/*

    E3: Variable subarray shift
    Write a circuit which constrains the following function:

    public inputs:
    an array `arr` of length 20
    `start`, an index guaranteed to be in `[0, 20)`
    `end`, an index guaranteed to be in `[0, 20)`
    It is also known that `start <= end`

    public outputs:
    an array `out` of length 20 such that
    the first `end - start` entries of `out` are the subarray `arr[start:end]`
    all other entries of `out` are 0

*/

/*

input:
{
    "arr": [43,234,75,12,39,20,5,9,22,67,35,11,107,18,43,85,28,130,45,72],
    "start": 2,
    "end": 10
}

*/


const input_arr = arr.map(witness);
const input_start = witness(start);
const input_end = witness(end);

// an array `arr` of length 20
checkLessThan(witness(input_arr.length), constant(20))

// `end`, an index guaranteed to be in `[0, 20)`
checkLessThan(input_end, constant(20));

// `start`, an index guaranteed to be in `[0, 20)`
// It is also known that `start <= end`
checkLessThan(input_end, input_start);

const v = sub(input_end, input_start).number();
const input_start_number = input_start.number();

let out = [];

// the first `end - start` entries of `out` are the subarray `arr[start:end]`
for (let i = 0; i < v; i++) {
    out.push(input_arr[input_start_number + i]);
}

// all other entries of `out` are 0.
for (let i = v; i < 20; i++) {
    out.push(constant(0));
}

// output
for (let i = 0; i < 20; i++) {
    makePublic(out[i]);
}





```

