const { toWad, fromWad, Side } = require("./constants");
const BigNumber = require('bignumber.js');

const log = (...message) => {
    console.log("  [TEST] >>", ...message);
};

const toBytes32 = s => {
    return web3.utils.fromAscii(s);
};

const fromBytes32 = b => {
    return web3.utils.toAscii(b);
};

const clone = x => JSON.parse(JSON.stringify(x));

const shouldFailOnError = async (message, func) => {
    try {
        await func();
    } catch (error) {
        assert.ok(
            error.message.includes(message),
            `exception should include "${message}", but get "${error.message}"`);
        return;
    }
    assert.fail(`should fail with "${message}"`);
};

const call = async (user, method) => {
    return await method.call();
};

const send = async (user, method, gasLimit = 8000000) => {
    return await method.send({ from: user, gasLimit: gasLimit });
};

const initializeToken = async (token, admin, balances) => {
    for (let i = 0; i < balances.length; i++) {
        const to = balances[i][0];
        const amount = toWad(balances[i][1]);
        await send(token.methods.mint(to, amount), admin);
    }
};

function createEVMSnapshot() {
    const id = Date.now() + Math.floor(Math.random() * 100000000);
    return new Promise((resolve, reject) => {
        web3.currentProvider.send({
            jsonrpc: '2.0',
            method: 'evm_snapshot',
            params: [],
            id: id,
        }, (err, resp) => {
            if (err) {
                reject(err);
                return;
            }
            resolve(resp.result);
        });
    });
}

function restoreEVMSnapshot(snapshotId) {
    const id = Date.now() + Math.floor(Math.random() * 100000000);
    return new Promise((resolve, reject) => {
        web3.currentProvider.send({
            jsonrpc: '2.0',
            method: 'evm_revert',
            params: [snapshotId],
            id: id,
        }, (err, resp) => {
            if (err) {
                reject(err);
                return;
            }
            if (resp.result !== true) {
                reject(resp);
                return;
            }
            resolve();
        });
    });
}

function increaseEvmTime(duration) {
    const id = Date.now() + Math.floor(Math.random() * 100000000);
    return new Promise((resolve, reject) => {
        web3.currentProvider.send({
            jsonrpc: '2.0',
            method: 'evm_increaseTime',
            params: [duration],
            id: id,
        }, (err, resp) => {
            if (err) {
                reject(err);
                return;
            }
            web3.currentProvider.send({
                jsonrpc: '2.0',
                method: 'evm_mine',
                params: [],
                id: id + 1,
            }, (err, resp) => {
                if (err) {
                    reject(err);
                    return;
                }
                resolve();
            });
        });
    });
}

function increaseEvmBlock(_web3) {
    if (typeof _web3 === 'undefined') {
        _web3 = web3;
    }
    const id = Date.now() + Math.floor(Math.random() * 100000000);
    return new Promise((resolve, reject) => {
        _web3.currentProvider.send({
            jsonrpc: '2.0',
            method: 'evm_mine',
            params: [],
            id: id,
        }, (err, resp) => {
            if (err) {
                reject(err);
                return;
            }
            resolve();
        });
    });
}

function stopMiner() {
    const id = Date.now() + Math.floor(Math.random() * 100000000);
    return new Promise((resolve, reject) => {
        web3.currentProvider.send({
            jsonrpc: '2.0',
            method: 'miner_stop',
            params: [],
            id: id,
        }, (err, resp) => {
            if (err) {
                reject(err);
                return;
            }
            resolve();
        });
    });
}

function startMiner() {
    const id = Date.now() + Math.floor(Math.random() * 100000000);
    return new Promise((resolve, reject) => {
        web3.currentProvider.send({
            jsonrpc: '2.0',
            method: 'miner_start',
            params: [],
            id: id,
        }, (err, resp) => {
            if (err) {
                reject(err);
                return;
            }
            resolve();
        });
    });
}

function assertApproximate(assert, actual, expected, limit) {
    if (typeof limit === 'undefined') {
        limit = new BigNumber("1e-12");
    }
    actual = new BigNumber(actual);
    if (!actual.isFinite()) {
        assert.fail(actual.toString(), expected.toString());
        return
    }
    expected = new BigNumber(expected);
    const abs = actual.minus(expected).abs();
    if (abs.gt(limit)) {
        assert.fail(actual.toString(), expected.toString());
        return
    }
}

function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

const inspect = async (user, perpetual, proxy, amm) => {
    const markPrice = await amm.currentMarkPrice.call();
    const position = await perpetual.getMarginAccount(user);
    console.log("  ACCOUNT STATISTIC for", user);
    console.log("  markPrice", fromWad(markPrice));
    console.log("  ┌─────────────────────────┬────────────");
    console.log("  │ COLLATERAL              │");
    console.log("  │   cashBalance           │", fromWad(position.cashBalance));
    console.log("  │ POSITION                │");
    console.log("  │   side                  │", position.side == Side.LONG ? "LONG" : (position.side == Side.SHORT ? "SHORT" : "FLAT"));
    console.log("  │   size                  │", fromWad(position.size));
    console.log("  │   entryValue            │", fromWad(position.entryValue));
    console.log("  │   entrySocialLoss       │", fromWad(position.entrySocialLoss));
    console.log("  │   entryFundingLoss      │", fromWad(position.entryFundingLoss));
    console.log("  │ Computed                │");
    console.log("  │   positionMargin        │", fromWad(await perpetual.positionMargin.call(user)));
    console.log("  │   marginBalance         │", fromWad(await perpetual.marginBalance.call(user)));
    console.log("  │   maintenanceMargin     │", fromWad(await perpetual.maintenanceMargin.call(user)));
    console.log("  │   pnl                   │", fromWad(await perpetual.pnl.call(user)));
    console.log("  │   availableMargin       │", fromWad(await perpetual.availableMargin.call(user)));
    if (user === proxy.address) {
        console.log("  │   availableMargin(Pool) │", fromWad(await amm.currentAvailableMargin.call()));
    }
    console.log("  │   isSafe                │", await perpetual.isSafe.call(user));
    console.log("  │   isBankrupt            │", await perpetual.isBankrupt.call(user));
    console.log("  └─────────────────────────┴────────────");
    console.log("");
};

const printFunding = async (amm, perpetual) => {
    const fundingState = await amm.currentFundingState.call();
    console.log(" FUNDING");
    console.log("  ┌───────────────────────────────┬────────────");
    console.log("  │ lastFundingTime               │", fundingState.lastFundingTime.toString());
    console.log("  │ lastPremium                   │", fromWad(fundingState.lastPremium));
    console.log("  │ lastEMAPremium                │", fromWad(fundingState.lastEMAPremium));
    console.log("  │ lastIndexPrice                │", fromWad(fundingState.lastIndexPrice));
    console.log("  │ accumulatedFundingPerContract │", fromWad(fundingState.accumulatedFundingPerContract));
    console.log("  │ fairPrice                     │", fromWad(await amm.currentFairPrice.call()));
    console.log("  │ premiumRate                   │", fromWad(await amm.currentPremiumRate.call()));
    console.log("  │ fundingRate                   │", fromWad(await amm.currentFundingRate.call()));
    console.log("  │ perp.totalSize                │", fromWad(await perpetual.totalSize(1)));
    console.log("  └───────────────────────────────┴────────────");
    console.log("");
};

module.exports = {
    log,
    toBytes32,
    fromBytes32,
    clone,
    shouldFailOnError,
    call,
    send,
    initializeToken,
    createEVMSnapshot,
    restoreEVMSnapshot,
    increaseEvmTime,
    increaseEvmBlock,
    stopMiner,
    startMiner,
    assertApproximate,
    sleep,
    inspect,
    printFunding
};