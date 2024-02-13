pragma circom 2.1.5;

include "circomlib/circuits/poseidon.circom";

template WalletSalt(num_ints) {
    signal input email_addr_ints[num_ints];
    signal input account_key;

    signal output salt;

    component poseidon = Poseidon(2+num_ints);
    for(var i=0; i<num_ints; i++) {
        poseidon.inputs[i] <== email_addr_ints[i];
    }
    poseidon.inputs[num_ints] <== account_key;
    poseidon.inputs[1+num_ints] <== 0;
    salt <== poseidon.out;
}

