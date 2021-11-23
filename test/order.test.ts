import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { assert } from "chai";
import { ethers } from "hardhat";

const { toWad } = require('./constants');
const { buildOrder, getOrderHash } = require('./order');

describe('order', () => {
    let testOrder: any;
    let testType: any;
    let accounts: string[] = [];
    let accs: SignerWithAddress[];

    const deploy = async () => {
        const TestOrder = await ethers.getContractFactory("TestOrder");
        const TestTypes = await ethers.getContractFactory("TestTypes");
        testOrder = await TestOrder.deploy();
        testType = await TestTypes.deploy();
        accs = await ethers.getSigners();
        for (const acc of accs) {
            let addr = await acc.getAddress();
            accounts.push(addr);
        }
    }

    before(async () => {
        await deploy();
    });

    it("test order", async () => {
        const admin = accounts[0];

        const u1 = accounts[4];
        const trader = u1
        const perpetualAddress = "0x4DA467821456Ca82De42fa691ddA08B24A4f0572";
        const offline = await buildOrder({
            trader: trader,
            amount: 1,
            price: 6000,
            version: 2,
            side: 'buy',
            type: 'market',
            expiredAt: 1589366656,
            salt: 666,
        }, perpetualAddress, admin);

        const orderParam = {
            trader: trader,
            broker: admin,
            amount: toWad(1),
            price: toWad(6000),
            data: offline.data,
            signature: offline.signature,
        };
        const order = await testOrder.getOrder(orderParam, perpetualAddress, admin);
        const orderHash = await testOrder.getOrderHash1(order);
        assert.equal(getOrderHash(offline), orderHash);

        assert.equal(await testOrder.expiredAt(orderParam), 1589366656)
        assert.equal(await testOrder.isSell(orderParam), false)
        assert.equal(await testOrder.isMarketOrder(orderParam), true);
        assert.equal(await testOrder.getPrice(orderParam), toWad(6000));
        assert.equal(await testOrder.isMarketBuy(orderParam), true);
        assert.equal(await testOrder.isMakerOnly(orderParam), false);
        assert.equal(await testOrder.isInversed(orderParam), false);
        assert.equal(await testOrder.side(orderParam), 2);
        assert.equal(await testOrder.makerFeeRate(orderParam), 0);
        assert.equal(await testOrder.takerFeeRate(orderParam), 0);
    });

    it("test order 2", async () => {
        const admin = accounts[0];
        const u1 = accounts[4];
        const trader = u1;
        const perpetualAddress = "0x4DA467821456Ca82De42fa691ddA08B24A4f0572";

        const offline = await buildOrder({
            trader: trader,
            amount: 1,
            price: 6000,
            version: 2,
            side: 'sell',
            type: 'limit',
            expiredAt: 1589366657,
            salt: 666,
            makerFeeRate: -15, // 100000
            takerFeeRate: 20
        }, perpetualAddress, admin);

        const orderParam = {
            trader: trader,
            amount: toWad(1),
            price: toWad(6000),
            data: offline.data,
            signature: offline.signature,
        };
        const order = await testOrder.getOrder(orderParam, perpetualAddress, admin);
        const orderHash = await testOrder.getOrderHash1(order);

        assert.equal(getOrderHash(offline), orderHash);

        assert.equal(await testOrder.expiredAt(orderParam), 1589366657)
        assert.equal(await testOrder.isSell(orderParam), true)
        assert.equal(await testOrder.isMarketOrder(orderParam), false);
        assert.equal(await testOrder.getPrice(orderParam), toWad(6000));
        assert.equal(await testOrder.isMarketBuy(orderParam), false);
        assert.equal(await testOrder.isMakerOnly(orderParam), false);
        assert.equal(await testOrder.isInversed(orderParam), false);
        assert.equal(await testOrder.side(orderParam), 1);
        assert.equal(await testOrder.makerFeeRate(orderParam), toWad(-0.000015));
        assert.equal(await testOrder.takerFeeRate(orderParam), toWad(0.00002));
    });

    it("test order 3", async () => {
        const admin = accounts[0];
        const u1 = accounts[4];
        const trader = u1;
        const perpetualAddress = "0x4DA467821456Ca82De42fa691ddA08B24A4f0572";

        const offline = await buildOrder({
            trader: trader,
            amount: 1,
            price: 6000,
            version: 2,
            side: 'sell',
            type: 'market',
            expiredAt: 1589366657,
            salt: 666,
            makerFeeRate: -15, // 100000
            takerFeeRate: 20,
            inversed: true,
        }, perpetualAddress, admin);

        const orderParam = {
            trader: trader,
            amount: toWad(1),
            price: toWad(6000),
            data: offline.data,
            signature: offline.signature,
        };
        const order = await testOrder.getOrder(orderParam, perpetualAddress, admin);
        const orderHash = await testOrder.getOrderHash1(order);
        assert.equal(getOrderHash(offline), orderHash);

        assert.equal(await testOrder.expiredAt(orderParam), 1589366657)
        assert.equal(await testOrder.isSell(orderParam), false)
        assert.equal(await testOrder.isMarketOrder(orderParam), true);
        assert.equal(await testOrder.getPrice(orderParam), "166666666666667");
        assert.equal(await testOrder.isMarketBuy(orderParam), true);
        assert.equal(await testOrder.isMakerOnly(orderParam), false);
        assert.equal(await testOrder.isInversed(orderParam), true);
        assert.equal(await testOrder.side(orderParam), 2);
        assert.equal(await testOrder.makerFeeRate(orderParam), toWad(-0.000015));
        assert.equal(await testOrder.takerFeeRate(orderParam), toWad(0.00002));
    });

    it("test order 3", async () => {
        assert.equal(await testType.counterSide(0), 0);
        assert.equal(await testType.counterSide(1), 2);
        assert.equal(await testType.counterSide(2), 1);
    });
});
