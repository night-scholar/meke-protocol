const BigNumber = require('bignumber.js');
const { toWad, fromWad, infinity } = require('./constants');
const { getWeb3 } = require("./order");

import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { assert } from "chai";
import { ethers } from "hardhat";

describe('TestCollateral', () => {
    let collateral: any;
    let globalConfig: any;
    let vault: any;
    let accounts: string[] = [];
    let accs: SignerWithAddress[];

    const broker = accounts[9];
    const admin = accounts[0];

    const u1 = accounts[4];
    const u2 = accounts[5];
    const u3 = accounts[6];

    const users = {
        broker,
        admin,
        u1,
        u2,
        u3,
    };

    const deploy = async (cDecimals = 18) => {
        let GlobalConfig = await ethers.getContractFactory("GlobalConfig");
        let Collateral = await ethers.getContractFactory("MyTestToken");
        let TestCollateral = await ethers.getContractFactory("TestCollateral");

        globalConfig = await GlobalConfig.deploy();
        collateral = await Collateral.deploy("TT", "TestToken", cDecimals);

        vault = await TestCollateral.deploy(globalConfig.address, collateral.address, cDecimals);

        accs = await ethers.getSigners();
        for (const acc of accs) {
            let addr = await acc.getAddress();
            accounts.push(addr);
        }
    };

    beforeEach(async () => {
        await deploy();
    })

    const cashBalanceOf = async (user: any) => {
        const cashAccount = await vault.getMarginAccount(user);
        return cashAccount.cashBalance;
    }

    describe("constructor - exceptions", () => {
        const u1 = accounts[4];
        const u2 = accounts[5];
        const u3 = accounts[6];

        const users = {
            broker,
            admin,
            u1,
            u2,
            u3,
        };

        it ("constructor - invalid decimals", async () => {
            let TestCollateral = await ethers.getContractFactory("TestCollateral");
            try {
                const col = await TestCollateral.deploy(globalConfig.address, "0x0000000000000000000000000000000000000000", 17);
                throw null;
            } catch (error) {
                // assert.ok(error.message.includes("invalid decimals"), error);
                console.log("errror ", error)
            }
        });

        it ("constructor - decimals out of range", async () => {
            let TestCollateral = await ethers.getContractFactory("TestCollateral");
            try {
                const col = await TestCollateral.deploy(globalConfig.address, "0x0000000000000000000000000000000000000000", 19);
                // throw null;
            } catch (error) {
                // assert.ok(error.message.includes("decimals out of range"));
                console.log("errror ", error)
                
            }
        });

        it ("constructor - decimals out of range", async () => {
            let TestCollateral = await ethers.getContractFactory("TestCollateral");

            try {
                const col = await TestCollateral.deploy(globalConfig.address, "0x0000000000000000000000000000000000000000", -1);
                // throw null;
            } catch (error) {
                // assert.ok(error.message.includes("decimals out of range"));
                console.log("errror ", error)

            }
        });
    });

    // describe("deposit / withdraw - ether", () => {
    //     let web3: any
    //     let u1: any;
    //     let u2;
    //     let u3;

    //     beforeEach(async () => {
    //         u1 = accounts[4];
    //         u2 = accounts[5];
    //         u3 = accounts[6];
    //         web3 = getWeb3();
    //         let TestCollateral = await ethers.getContractFactory("TestCollateral");
    //         vault = await TestCollateral.deploy(globalConfig.address, "0x0000000000000000000000000000000000000000", 18)

    //     });

    //     it('isTokenizedCollateral', async () => {
    //         assert.ok(!(await vault.isTokenizedCollateralPublic()));
    //     });

    //     it('deposit', async () => {
    //         let tx, gas;
    //         let b0 = await web3.eth.getBalance(u1);

    //         let m = await vault.getMarginAccount(u1);
    //         tx = await vault.depositPublic(toWad(0.01), {from: u1, value: toWad(0.01)});
    //         let bal = await cashBalanceOf(u1);

    //         assert.equal(bal.toString(), toWad(0.01));

    //         gas = new BigNumber(20 * 10 ** 9).times(new BigNumber(tx.receipt.gasUsed));

    //         tx = await vault.depositPublic(toWad(0.01), { from: u1, value: toWad(0.01), gasPrice: 20 * 10 ** 9 });
    //         assert.equal(await cashBalanceOf(u1), toWad(0.02));
    //         gas = gas.plus(new BigNumber(20 * 10 ** 9).times(new BigNumber(tx.receipt.gasUsed)));

    //         let b1 = new BigNumber((await web3.eth.getBalance(u1)).toString());
    //         assert.equal(b1.plus(gas).plus(new BigNumber(toWad(0.02))).toFixed(), b0.toString());

    //         tx = await vault.depositPublic(toWad(0.02), { from: u1, value: toWad(0.02), gasPrice: 20 * 10 ** 9 });
    //         assert.equal(await cashBalanceOf(u1), toWad(0.04));
    //         gas = gas.plus(new BigNumber(20 * 10 ** 9).times(new BigNumber(tx.receipt.gasUsed)));

    //         let b2 = new BigNumber((await web3.eth.getBalance(u1)).toString());
    //         assert.equal(b2.plus(gas).plus(new BigNumber(toWad(0.04))).toFixed(), b0.toString());
    //     });

    //     it('withdraw', async () => {
    //         await vault.depositPublic(toWad(0.01), { from: u1, value: toWad(0.01) });
    //         assert.equal(fromWad(await cashBalanceOf(u1)), 0.01);
    //         await vault.withdrawPublic(toWad(0.005), { from: u1 });
    //         assert.equal(await cashBalanceOf(u1), toWad(0.005));
    //     });

    //     it('pullCollateral', async() => {
    //         await collateral.transfer(u1, toWad(1000));
    //         const balanceBefore = await web3.eth.getBalance(u1);
    //         assert.equal(await vault.pullCollateralPublic.call(u1, toWad(1000)), toWad(1000));
    //         const balanceAfter = await web3.eth.getBalance(u1);
    //         assert.equal(balanceBefore, balanceAfter);
    //     });

    //     it('pushCollateral', async() => {
    //         await vault.depositPublic(toWad(1000), { from: admin, value: toWad(1000) });
    //         assert.equal(await web3.eth.getBalance(vault.address), toWad(1000));

    //         const balanceBefore = await web3.eth.getBalance(u1);
    //         await vault.pushCollateralPublic(u1, toWad(1000));
    //         const balanceAfter = await web3.eth.getBalance(u1);
    //         assert.equal(new BigNumber(balanceAfter).minus(new BigNumber(balanceBefore)), toWad(1000));

    //         try {
    //             await vault.pushCollateralPublic(u1, 1);
    //             throw null;
    //         } catch (error) {
    //             assert.ok(error.message.includes("insufficient balance"));
    //         }
    //     });
    // });

    // describe("deposit / withdraw - token", async () => {
    //     beforeEach(deploy);

    //     it('isTokenizedCollateral', async () => {
    //         assert.ok(await vault.isTokenizedCollateralPublic());
    //     });

    //     it('deposit', async () => {
    //         await collateral.transfer(u1, toWad(10));
    //         await collateral.approve(vault.address, infinity, { from: u1 });
    //         await vault.depositPublic(toWad(3.1415), { from: u1 });
    //         assert.equal(await cashBalanceOf(u1), toWad(3.1415));

    //         assert.equal(await collateral.balanceOf(u1), toWad(10, -3.1415));
    //     });

    //     it('deposit too much', async () => {
    //         try {
    //             await vault.depositPublic(toWad(30.1415), { from: u1 });
    //             throw null;
    //         } catch (error) {
    //             assert.ok(error.message.includes("low-level call failed"), error);
    //         }
    //     });

    //     it('withdraw', async () => {
    //         await collateral.transfer(u1, toWad(10));
    //         await collateral.approve(vault.address, infinity, { from: u1 });

    //         await vault.depositPublic(toWad(10), { from: u1 });

    //         await vault.withdrawPublic(toWad(3.1415), { from: u1 });
    //         assert.equal(await cashBalanceOf(u1), toWad(6.8585));

    //         await vault.withdrawPublic(toWad(6.0), { from: u1 });
    //         assert.equal(await cashBalanceOf(u1), toWad(0.8585));

    //         await vault.withdrawPublic(toWad(0.8585), { from: u1 });
    //         assert.equal(await cashBalanceOf(u1), toWad(0));

    //         try {
    //             await vault.withdrawPublic(1, { from: u1 });
    //             throw null;
    //         } catch (error) {
    //             assert.ok(error.message.includes("insufficient balance"));
    //         }
    //     });

    //     it('pullCollateral', async() => {
    //         await collateral.approve(vault.address, infinity, { from: u1 });
    //         try {
    //             assert.equal(await vault.pullCollateralPublic(u1, toWad(1000)), toWad(1000));
    //             throw null;
    //         } catch (error) {
    //             assert.ok(error.message.includes("low-level call failed"), error);
    //         }
    //         await collateral.transfer(u1, toWad(1000));
    //         assert.equal(await collateral.balanceOf(u1), toWad(1000));
    //         assert.equal(await vault.pullCollateralPublic.call(u1, toWad(1000)), toWad(1000));
    //         await vault.pullCollateralPublic(u1, toWad(1000));
    //         assert.equal(await collateral.balanceOf(u1), 0);

    //     });

    //     it('pushCollateral', async() => {
    //         await collateral.approve(vault.address, infinity, { from: admin });
    //         await collateral.transfer(vault.address, toWad(1000));

    //         assert.equal(await collateral.balanceOf(vault.address), toWad(1000));
    //         assert.equal(await collateral.balanceOf(u1), toWad(0));
    //         await vault.pushCollateralPublic(u1, toWad(1000));
    //         assert.equal(await collateral.balanceOf(vault.address), toWad(0));
    //         assert.equal(await collateral.balanceOf(u1), toWad(1000));

    //         try {
    //             await vault.pushCollateralPublic(u1, 1);
    //             throw null;
    //         } catch (error) {
    //             assert.ok(error.message.includes("low-level call failed"));
    //         }
    //     });

    // });

    // describe("decimals", async () => {
    //     const toDecimals = (x: number, decimals: number) => {
    //         let n = new BigNumber(x).times(new BigNumber(10 ** decimals));
    //         return n.toFixed();
    //     };

    //     it("invalid decimals", async () => {
    //         await deploy(18);
    //         try {
    //             await deploy(19);
    //         } catch (error) {
    //             assert.ok(error.message.includes("decimals out of range"), error);
    //         }
    //     });

    //     it("decimals ~ 0 => 18", async () => {
    //         for (var i = 0; i <= 18; i++) {
    //             await deploy(i);

    //             const raw = toDecimals(1, i);
    //             const wad = toWad(1);

    //             await collateral.transfer(u1, raw);
    //             await collateral.approve(vault.address, infinity, { from: u1 });
    //             assert.equal(await collateral.balanceOf(u1), raw);

    //             await vault.depositPublic(raw, { from: u1 });
    //             assert.equal(await cashBalanceOf(u1), wad);

    //             await vault.withdrawPublic(raw, { from: u1 });
    //             assert.equal(await cashBalanceOf(u1), 0);

    //             assert.equal(await collateral.balanceOf(u1), raw);

    //             assert.equal(await vault.toWadPublic(raw), wad);
    //             assert.equal(await vault.toCollateralPublic(wad), raw);
    //         }
    //     });
    // });

});