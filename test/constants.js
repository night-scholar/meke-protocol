const BigNumber = require('bignumber.js');
BigNumber.config({ EXPONENTIAL_AT: 1000 });

const _weis = new BigNumber('1000000000000000000');

const toWei = (...xs) => {
    let sum = new BigNumber(0);
    for (var x of xs) {
        sum = sum.plus(new BigNumber(x).times(_weis));
    }
    return sum.toFixed();
};

const fromWei = x => {
    return new BigNumber(x).div(_weis).toString();
};

const _wad = new BigNumber('1000000000000000000');

const toWad = (...xs) => {
    let sum = new BigNumber(0);
    for (var x of xs) {
        sum = sum.plus(new BigNumber(x).times(_wad));
    }
    return sum.toFixed();
};

const fromWad = x => {
    return new BigNumber(x).div(_wad).toString();
};

const toDecimal = (x, decimals) => {
    return new BigNumber(x).shiftedBy(decimals).toString();
}

const fromDecimal = (x, decimals) => {
    return new BigNumber(x).shiftedBy(-decimals).toString();
}

// const infinity = '999999999999999999999999999999999999999999';
const infinity = '9999999999999999999999999999'; // less than uint96

const Side = {
    FLAT: 0,
    SHORT: 1,
    LONG: 2,
}

module.exports = {
    toWei,
    fromWei,
    toWad,
    fromWad,
    toDecimal,
    fromDecimal,
    infinity,
    Side,
};
