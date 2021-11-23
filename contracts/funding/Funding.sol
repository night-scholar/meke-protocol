// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.7.6;
pragma abicoder v2;

import {LibMathSigned, LibMathUnsigned} from "../lib/LibMath.sol";

import "../lib/LibTypes.sol";
import "../interface/IPriceFeeder.sol";
import "../interface/IPerpetual.sol";
import "./FundingGovernance.sol";


contract Funding is FundingGovernance {
    using LibMathSigned for int256;
    using LibMathUnsigned for uint256;

    int256 private constant FUNDING_PERIOD = 28800; // 8 * 3600;
    uint256 public _fairPrice;

    event UpdateFundingRate(LibTypes.FundingState fundingState);

    constructor(
        address _globalConfig,
        address _perpetualProxy,
        address _priceFeeder
    ) FundingGovernance(_globalConfig)
    {
        priceFeeder = IPriceFeeder(_priceFeeder);
        perpetualProxy = IPerpetual(_perpetualProxy);
    }

    /**
     * @notice Index price.
     *
     * Re-read the oracle price instead of the cached value.
     */
    function indexPrice() public view returns (uint256 price, uint256 timestamp) {
        (price, timestamp) = priceFeeder.price();
        require(price != 0, "dangerous index price");
    }

    /**
     * @notice FundingState.
     *
     * Note: last* functions (lastFundingState, lastFairPrice, etc.) are calculated based on
     *       the on-chain fundingState. current* functions are calculated based on the current timestamp.
     */
    function lastFundingState() public view returns (LibTypes.FundingState memory) {
        return fundingState;
    }

    /**
     * @notice FairPrice.
     *
     * Note: last* functions (lastFundingState, lastFairPrice, etc.) are calculated based on
     *       the on-chain fundingState. current* functions are calculated based on the current timestamp.
     */
    function lastFairPrice() internal view returns (uint256) {
        return _fairPrice;
    }

    /**
     * @notice Premium.
     *
     * Note: last* functions (lastFundingState, lastFairPrice, etc.) are calculated based on
     *       the on-chain fundingState. current* functions are calculated based on the current timestamp.
     */
    function lastPremium() internal view returns (int256) {
        return premium();
    }

    /**
     * @notice EMAPremium.
     *
     * Note: last* functions (lastFundingState, lastFairPrice, etc.) are calculated based on
     *       on-chain fundingState. current* functions are calculated based on the current timestamp.
     */
    function lastEMAPremium() internal view returns (int256) {
        return fundingState.lastEMAPremium;
    }

    /**
     * @notice MarkPrice.
     *
     * Note: last* functions (lastFundingState, lastFairPrice, etc.) are calculated based on
     *       the on-chain fundingState. current* functions are calculated based on the current timestamp.
     */
    function lastMarkPrice() internal view returns (uint256) {
        int256 index = fundingState.lastIndexPrice.toInt256();
        int256 limit = index.wmul(governance.markPremiumLimit);
        int256 p = index.add(lastEMAPremium());
        p = p.min(index.add(limit));
        p = p.max(index.sub(limit));
        return p.max(0).toUint256();
    }

    /**
     * @notice PremiumRate.
     *
     * Note: last* functions (lastFundingState, lastFairPrice, etc.) are calculated based on
     *       the on-chain fundingState. current* functions are calculated based on the current timestamp.
     */
    function lastPremiumRate() internal view returns (int256) {
        int256 index = fundingState.lastIndexPrice.toInt256();
        int256 rate = lastMarkPrice().toInt256();
        rate = rate.sub(index).wdiv(index);
        return rate;
    }

    /**
     * @notice FundingRate.
     *
     * Note: last* functions (lastFundingState, lastFairPrice, etc.) are calculated based on
     *       the on-chain fundingState. current* functions are calculated based on the current timestamp.
     */
    function lastFundingRate() public view returns (int256) {
        int256 rate = lastPremiumRate();
        return rate.max(governance.fundingDampener).add(rate.min(-governance.fundingDampener));
    }

    // Public functions

    /**
     * @notice FundingState.
     *
     * Note: current* functions (currentFundingState, currentFairPrice, etc.) are calculated based on
     *       the current timestamp. current* functions are calculated based on the on-chain fundingState.
     */
    function currentFundingState() public returns (LibTypes.FundingState memory) {
        funding();
        return fundingState;
    }

    /**
     * @notice FairPrice.
     *
     * Note: current* functions (currentFundingState, currentFairPrice, etc.) are calculated based on
     *       the current timestamp. current* functions are calculated based on the on-chain fundingState.
     */
    function currentFairPrice() public returns (uint256) {
        funding();
        return lastFairPrice();
    }

    /**
     * @notice Premium.
     *
     * Note: current* functions (currentFundingState, currentFairPrice, etc.) are calculated based on
     *       the current timestamp. current* functions are calculated based on the on-chain fundingState.
     */
    function currentPremium() public returns (int256) {
        funding();
        return lastPremium();
    }

    /**
     * @notice MarkPrice.
     *
     * Note: current* functions (currentFundingState, currentFairPrice, etc.) are calculated based on
     *       the current timestamp. current* functions are calculated based on the on-chain fundingState.
     */
    function currentMarkPrice() public returns (uint256) {
        funding();
        return lastMarkPrice();
    }

    /**
     * @notice PremiumRate.
     *
     * Note: current* functions (currentFundingState, currentFairPrice, etc.) are calculated based on
     *       the current timestamp. current* functions are calculated based on the on-chain fundingState.
     */
    function currentPremiumRate() public returns (int256) {
        funding();
        return lastPremiumRate();
    }

    /**
     * @notice FundingRate.
     *
     * Note: current* functions (currentFundingState, currentFairPrice, etc.) are calculated based on
     *       the current timestamp. current* functions are calculated based on the on-chain fundingState.
     */
    function currentFundingRate() public returns (int256) {
        funding();
        return lastFundingRate();
    }

    /**
     * @notice AccumulatedFundingPerContract.
     *
     * Note: current* functions (currentFundingState, currentFairPrice, etc.) are calculated based on
     *       the current timestamp. current* functions are calculated based on the on-chain fundingState.
     */
    function currentAccumulatedFundingPerContract() public returns (int256) {
        funding();
        return fundingState.accumulatedFundingPerContract;
    }

    function initFunding() public {
        require(perpetualProxy.status() == LibTypes.Status.NORMAL, "wrong perpetual status");

        uint256 blockTime = getBlockTimestamp();
        uint256 newIndexPrice;
        uint256 newIndexTimestamp;
        (newIndexPrice, newIndexTimestamp) = indexPrice();

        initFunding(newIndexPrice, blockTime);
        forceFunding();
    }

    // Internal helpers

    /**
     * @notice In order to mock the block.timestamp
     */
    function getBlockTimestamp() internal view returns (uint256) {
        // solium-disable-next-line security/no-block-members
        return block.timestamp;
    }

    /**
     * @notice a gas-optimized version of lastFairPrice
     */
    function fairPriceFromPoolAccount() internal view returns (uint256) {
        return _fairPrice;
    }

    function setFairPrice(uint256 price) external onlyAuthorized {
        _fairPrice = price;
        forceFunding();
    }

    /**
     * @notice a gas-optimized version of lastPremium
     */
    function premium() internal view returns (int256) {
        int256 p = _fairPrice.toInt256();
        p = p.sub(fundingState.lastIndexPrice.toInt256());
        return p;
    }

    /**
     * @notice Init the fundingState. This function should be called before a funding().
     *
     * @param newIndexPrice Index price.
     * @param blockTime Use this timestamp instead of the time that the index price is generated, because this is the first initialization.
     */
    function initFunding(uint256 newIndexPrice, uint256 blockTime) private {
        require(fundingState.lastFundingTime == 0, "already initialized");
        fundingState.lastFundingTime = blockTime;
        fundingState.lastIndexPrice = newIndexPrice;
        fundingState.lastPremium = 0;
        fundingState.lastEMAPremium = 0;
    }

    /**
     * @notice current* functions need a funding() before return our states.
     *
     * Note: Will skip funding() other than NORMAL
     *
     * There are serveral conditions for change the funding state:
     * Condition 1: time.
     * Condition 2: indexPrice.
     * Condition 3: fairPrice. This condition is not covered in this function. We hand over to forceFunding.
     */
    function funding() internal {
        if (perpetualProxy.status() != LibTypes.Status.NORMAL) {
            return;
        }
        uint256 blockTime = getBlockTimestamp();
        uint256 newIndexPrice;
        uint256 newIndexTimestamp;
        (newIndexPrice, newIndexTimestamp) = indexPrice();
        if (
            blockTime != fundingState.lastFundingTime || // condition 1
            newIndexPrice != fundingState.lastIndexPrice || // condition 2, especially when updateIndex and buy/sell are in the same block
            newIndexTimestamp > fundingState.lastFundingTime // condition 2
        ) {
            forceFunding(blockTime, newIndexPrice, newIndexTimestamp);
        }
    }

    /**
     * @notice Update fundingState without checking whether the funding condition changes.
     *
     * This function also splits the funding process into 2 parts:
     * 1. funding from [lastFundingTime, lastIndexTimestamp)
     * 2. funding from [lastIndexTimestamp, blockTime)
     *
     */
    function forceFunding() internal {
        require(perpetualProxy.status() == LibTypes.Status.NORMAL, "wrong perpetual status");
        uint256 blockTime = getBlockTimestamp();
        uint256 newIndexPrice;
        uint256 newIndexTimestamp;
        (newIndexPrice, newIndexTimestamp) = indexPrice();
        forceFunding(blockTime, newIndexPrice, newIndexTimestamp);
    }

    /**
     * @notice Update fundingState without checking whether the funding condition changes.
     *
     * This function also splits the funding process into 2 parts:
     * 1. funding from [lastFundingTime, lastIndexTimestamp)
     * 2. funding from [lastIndexTimestamp, blockTime)
     *
     * @param blockTime The real end time.
     * @param newIndexPrice The latest index price.
     * @param newIndexTimestamp The timestamp of the latest index.
     */
    function forceFunding(uint256 blockTime, uint256 newIndexPrice, uint256 newIndexTimestamp) private {
        if (fundingState.lastFundingTime == 0) {
            // funding initialization required. but in this case, it's safe to just do nothing and return
            return;
        }
        if (newIndexTimestamp > fundingState.lastFundingTime) {
            // the 1st update
            nextStateWithTimespan(newIndexPrice, newIndexTimestamp);
        }
        // the 2nd update;
        nextStateWithTimespan(newIndexPrice, blockTime);

        emit UpdateFundingRate(fundingState);
    }

    /**
     * @notice Update fundingState from the lastFundingTime to the given time.
     *
     * This function also adds Acc / (8*3600) into accumulatedFundingPerContract, where Acc is accumulated
     * funding payment per position since lastFundingTime
     *
     * @param newIndexPrice New index price.
     * @param endTimestamp The given end time.
     */
    function nextStateWithTimespan(
        uint256 newIndexPrice,
        uint256 endTimestamp
    ) private {
        require(fundingState.lastFundingTime != 0, "funding initialization required");
        require(endTimestamp >= fundingState.lastFundingTime, "time steps (n) must be positive");

        // update ema
        if (fundingState.lastFundingTime != endTimestamp) {
            int256 timeDelta = endTimestamp.sub(fundingState.lastFundingTime).toInt256();
            int256 acc;
            (fundingState.lastEMAPremium, acc) = getAccumulatedFunding(
                timeDelta,
                fundingState.lastEMAPremium,
                fundingState.lastPremium,
                fundingState.lastIndexPrice.toInt256() // ema is according to the old index
            );
            fundingState.accumulatedFundingPerContract = fundingState.accumulatedFundingPerContract.add(
                acc.div(FUNDING_PERIOD)
            );
            fundingState.lastFundingTime = endTimestamp;
        }

        // always update
        fundingState.lastIndexPrice = newIndexPrice; // should update before premium()
        fundingState.lastPremium = premium();
    }

    /**
     * @notice Solve t in emaPremium == y equation
     *
     * @param y Required function output.
     * @param v0 LastEMAPremium.
     * @param _lastPremium LastPremium.
     */
    function timeOnFundingCurve(
        int256 y,
        int256 v0,
        int256 _lastPremium
    )
        internal
        view
        returns (
            int256 t // normal int, not WAD
        )
    {
        require(y != _lastPremium, "no solution 1 on funding curve");
        t = y.sub(_lastPremium);
        t = t.wdiv(v0.sub(_lastPremium));
        require(t > 0, "no solution 2 on funding curve");
        require(t < LibMathSigned.WAD(), "no solution 3 on funding curve");
        t = t.wln();
        t = t.wdiv(emaAlpha2Ln);
        t = t.ceil(LibMathSigned.WAD()) / LibMathSigned.WAD();
    }

    /**
     * @notice Sum emaPremium curve between [x, y)
     *
     * @param x Begin time. normal int, not WAD.
     * @param y End time. normal int, not WAD.
     * @param v0 LastEMAPremium.
     * @param _lastPremium LastPremium.
     */
    function integrateOnFundingCurve(
        int256 x,
        int256 y,
        int256 v0,
        int256 _lastPremium
    ) internal view returns (int256 r) {
        require(x <= y, "integrate reversed");
        r = v0.sub(_lastPremium);
        r = r.wmul(emaAlpha2.wpowi(x).sub(emaAlpha2.wpowi(y)));
        r = r.wdiv(governance.emaAlpha);
        r = r.add(_lastPremium.mul(y.sub(x)));
    }

   /**
     * @notice The intermediate variables required by getAccumulatedFunding. This is only used to move stack
     *         variables to storage variables.
     */
    struct AccumulatedFundingCalculator {
        int256 vLimit;
        int256 vDampener;
        int256 t1; // normal int, not WAD
        int256 t2; // normal int, not WAD
        int256 t3; // normal int, not WAD
        int256 t4; // normal int, not WAD
    }

    /**
     * @notice Calculate the `Acc`. Sigma the funding rate curve while considering the limit and dampener. There are
     *         4 boundary points on the curve (-GovMarkPremiumLimit, -GovFundingDampener, +GovFundingDampener, +GovMarkPremiumLimit)
     *         which segment the curve into 5 parts, so that the calculation can be arranged into 5 * 5 = 25 cases.
     *         In order to reduce the amount of calculation, the code is expanded into 25 branches.
     *
     * @param n Time span. normal int, not WAD.
     * @param v0 LastEMAPremium.
     * @param _lastPremium LastPremium.
     * @param _lastIndexPrice LastIndexPrice.
     */
    function getAccumulatedFunding(
        int256 n,
        int256 v0,
        int256 _lastPremium,
        int256 _lastIndexPrice
    )
        internal
        view
        returns (
            int256 vt, // new LastEMAPremium
            int256 acc
        )
    {
        require(n > 0, "we can't go back in time");
        AccumulatedFundingCalculator memory ctx;
        vt = v0.sub(_lastPremium);
        vt = vt.wmul(emaAlpha2.wpowi(n));
        vt = vt.add(_lastPremium);
        ctx.vLimit = governance.markPremiumLimit.wmul(_lastIndexPrice);
        ctx.vDampener = governance.fundingDampener.wmul(_lastIndexPrice);
        if (v0 <= -ctx.vLimit) {
            // part A
            if (vt <= -ctx.vLimit) {
                acc = (-ctx.vLimit).add(ctx.vDampener).mul(n);
            } else if (vt <= -ctx.vDampener) {
                ctx.t1 = timeOnFundingCurve(-ctx.vLimit, v0, _lastPremium);
                acc = (-ctx.vLimit).mul(ctx.t1);
                acc = acc.add(integrateOnFundingCurve(ctx.t1, n, v0, _lastPremium));
                acc = acc.add(ctx.vDampener.mul(n));
            } else if (vt <= ctx.vDampener) {
                ctx.t1 = timeOnFundingCurve(-ctx.vLimit, v0, _lastPremium);
                ctx.t2 = timeOnFundingCurve(-ctx.vDampener, v0, _lastPremium);
                acc = (-ctx.vLimit).mul(ctx.t1);
                acc = acc.add(integrateOnFundingCurve(ctx.t1, ctx.t2, v0, _lastPremium));
                acc = acc.add(ctx.vDampener.mul(ctx.t2));
            } else if (vt <= ctx.vLimit) {
                ctx.t1 = timeOnFundingCurve(-ctx.vLimit, v0, _lastPremium);
                ctx.t2 = timeOnFundingCurve(-ctx.vDampener, v0, _lastPremium);
                ctx.t3 = timeOnFundingCurve(ctx.vDampener, v0, _lastPremium);
                acc = (-ctx.vLimit).mul(ctx.t1);
                acc = acc.add(integrateOnFundingCurve(ctx.t1, ctx.t2, v0, _lastPremium));
                acc = acc.add(integrateOnFundingCurve(ctx.t3, n, v0, _lastPremium));
                acc = acc.add(ctx.vDampener.mul(ctx.t2.sub(n).add(ctx.t3)));
            } else {
                ctx.t1 = timeOnFundingCurve(-ctx.vLimit, v0, _lastPremium);
                ctx.t2 = timeOnFundingCurve(-ctx.vDampener, v0, _lastPremium);
                ctx.t3 = timeOnFundingCurve(ctx.vDampener, v0, _lastPremium);
                ctx.t4 = timeOnFundingCurve(ctx.vLimit, v0, _lastPremium);
                acc = (-ctx.vLimit).mul(ctx.t1);
                acc = acc.add(integrateOnFundingCurve(ctx.t1, ctx.t2, v0, _lastPremium));
                acc = acc.add(integrateOnFundingCurve(ctx.t3, ctx.t4, v0, _lastPremium));
                acc = acc.add(ctx.vLimit.mul(n.sub(ctx.t4)));
                acc = acc.add(ctx.vDampener.mul(ctx.t2.sub(n).add(ctx.t3)));
            }
        } else if (v0 <= -ctx.vDampener) {
            // part B
            if (vt <= -ctx.vLimit) {
                ctx.t4 = timeOnFundingCurve(-ctx.vLimit, v0, _lastPremium);
                acc = integrateOnFundingCurve(0, ctx.t4, v0, _lastPremium);
                acc = acc.add((-ctx.vLimit).mul(n.sub(ctx.t4)));
                acc = acc.add(ctx.vDampener.mul(n));
            } else if (vt <= -ctx.vDampener) {
                acc = integrateOnFundingCurve(0, n, v0, _lastPremium);
                acc = acc.add(ctx.vDampener.mul(n));
            } else if (vt <= ctx.vDampener) {
                ctx.t2 = timeOnFundingCurve(-ctx.vDampener, v0, _lastPremium);
                acc = integrateOnFundingCurve(0, ctx.t2, v0, _lastPremium);
                acc = acc.add(ctx.vDampener.mul(ctx.t2));
            } else if (vt <= ctx.vLimit) {
                ctx.t2 = timeOnFundingCurve(-ctx.vDampener, v0, _lastPremium);
                ctx.t3 = timeOnFundingCurve(ctx.vDampener, v0, _lastPremium);
                acc = integrateOnFundingCurve(0, ctx.t2, v0, _lastPremium);
                acc = acc.add(integrateOnFundingCurve(ctx.t3, n, v0, _lastPremium));
                acc = acc.add(ctx.vDampener.mul(ctx.t2.sub(n).add(ctx.t3)));
            } else {
                ctx.t2 = timeOnFundingCurve(-ctx.vDampener, v0, _lastPremium);
                ctx.t3 = timeOnFundingCurve(ctx.vDampener, v0, _lastPremium);
                ctx.t4 = timeOnFundingCurve(ctx.vLimit, v0, _lastPremium);
                acc = integrateOnFundingCurve(0, ctx.t2, v0, _lastPremium);
                acc = acc.add(integrateOnFundingCurve(ctx.t3, ctx.t4, v0, _lastPremium));
                acc = acc.add(ctx.vLimit.mul(n.sub(ctx.t4)));
                acc = acc.add(ctx.vDampener.mul(ctx.t2.sub(n).add(ctx.t3)));
            }
        } else if (v0 <= ctx.vDampener) {
            // part C
            if (vt <= -ctx.vLimit) {
                ctx.t3 = timeOnFundingCurve(-ctx.vDampener, v0, _lastPremium);
                ctx.t4 = timeOnFundingCurve(-ctx.vLimit, v0, _lastPremium);
                acc = integrateOnFundingCurve(ctx.t3, ctx.t4, v0, _lastPremium);
                acc = acc.add((-ctx.vLimit).mul(n.sub(ctx.t4)));
                acc = acc.add(ctx.vDampener.mul(n.sub(ctx.t3)));
            } else if (vt <= -ctx.vDampener) {
                ctx.t3 = timeOnFundingCurve(-ctx.vDampener, v0, _lastPremium);
                acc = integrateOnFundingCurve(ctx.t3, n, v0, _lastPremium);
                acc = acc.add(ctx.vDampener.mul(n.sub(ctx.t3)));
            } else if (vt <= ctx.vDampener) {
                acc = 0;
            } else if (vt <= ctx.vLimit) {
                ctx.t3 = timeOnFundingCurve(ctx.vDampener, v0, _lastPremium);
                acc = integrateOnFundingCurve(ctx.t3, n, v0, _lastPremium);
                acc = acc.sub(ctx.vDampener.mul(n.sub(ctx.t3)));
            } else {
                ctx.t3 = timeOnFundingCurve(ctx.vDampener, v0, _lastPremium);
                ctx.t4 = timeOnFundingCurve(ctx.vLimit, v0, _lastPremium);
                acc = integrateOnFundingCurve(ctx.t3, ctx.t4, v0, _lastPremium);
                acc = acc.add(ctx.vLimit.mul(n.sub(ctx.t4)));
                acc = acc.sub(ctx.vDampener.mul(n.sub(ctx.t3)));
            }
        } else if (v0 <= ctx.vLimit) {
            // part D
            if (vt <= -ctx.vLimit) {
                ctx.t2 = timeOnFundingCurve(ctx.vDampener, v0, _lastPremium);
                ctx.t3 = timeOnFundingCurve(-ctx.vDampener, v0, _lastPremium);
                ctx.t4 = timeOnFundingCurve(-ctx.vLimit, v0, _lastPremium);
                acc = integrateOnFundingCurve(0, ctx.t2, v0, _lastPremium);
                acc = acc.add(integrateOnFundingCurve(ctx.t3, ctx.t4, v0, _lastPremium));
                acc = acc.add((-ctx.vLimit).mul(n.sub(ctx.t4)));
                acc = acc.add(ctx.vDampener.mul(n.sub(ctx.t3).sub(ctx.t2)));
            } else if (vt <= -ctx.vDampener) {
                ctx.t2 = timeOnFundingCurve(ctx.vDampener, v0, _lastPremium);
                ctx.t3 = timeOnFundingCurve(-ctx.vDampener, v0, _lastPremium);
                acc = integrateOnFundingCurve(0, ctx.t2, v0, _lastPremium);
                acc = acc.add(integrateOnFundingCurve(ctx.t3, n, v0, _lastPremium));
                acc = acc.add(ctx.vDampener.mul(n.sub(ctx.t3).sub(ctx.t2)));
            } else if (vt <= ctx.vDampener) {
                ctx.t2 = timeOnFundingCurve(ctx.vDampener, v0, _lastPremium);
                acc = integrateOnFundingCurve(0, ctx.t2, v0, _lastPremium);
                acc = acc.sub(ctx.vDampener.mul(ctx.t2));
            } else if (vt <= ctx.vLimit) {
                acc = integrateOnFundingCurve(0, n, v0, _lastPremium);
                acc = acc.sub(ctx.vDampener.mul(n));
            } else {
                ctx.t4 = timeOnFundingCurve(ctx.vLimit, v0, _lastPremium);
                acc = integrateOnFundingCurve(0, ctx.t4, v0, _lastPremium);
                acc = acc.add(ctx.vLimit.mul(n.sub(ctx.t4)));
                acc = acc.sub(ctx.vDampener.mul(n));
            }
        } else {
            // part E
            if (vt <= -ctx.vLimit) {
                ctx.t1 = timeOnFundingCurve(ctx.vLimit, v0, _lastPremium);
                ctx.t2 = timeOnFundingCurve(ctx.vDampener, v0, _lastPremium);
                ctx.t3 = timeOnFundingCurve(-ctx.vDampener, v0, _lastPremium);
                ctx.t4 = timeOnFundingCurve(-ctx.vLimit, v0, _lastPremium);
                acc = ctx.vLimit.mul(ctx.t1);
                acc = acc.add(integrateOnFundingCurve(ctx.t1, ctx.t2, v0, _lastPremium));
                acc = acc.add(integrateOnFundingCurve(ctx.t3, ctx.t4, v0, _lastPremium));
                acc = acc.add((-ctx.vLimit).mul(n.sub(ctx.t4)));
                acc = acc.add(ctx.vDampener.mul(n.sub(ctx.t3).sub(ctx.t2)));
            } else if (vt <= -ctx.vDampener) {
                ctx.t1 = timeOnFundingCurve(ctx.vLimit, v0, _lastPremium);
                ctx.t2 = timeOnFundingCurve(ctx.vDampener, v0, _lastPremium);
                ctx.t3 = timeOnFundingCurve(-ctx.vDampener, v0, _lastPremium);
                acc = ctx.vLimit.mul(ctx.t1);
                acc = acc.add(integrateOnFundingCurve(ctx.t1, ctx.t2, v0, _lastPremium));
                acc = acc.add(integrateOnFundingCurve(ctx.t3, n, v0, _lastPremium));
                acc = acc.add(ctx.vDampener.mul(n.sub(ctx.t3).sub(ctx.t2)));
            } else if (vt <= ctx.vDampener) {
                ctx.t1 = timeOnFundingCurve(ctx.vLimit, v0, _lastPremium);
                ctx.t2 = timeOnFundingCurve(ctx.vDampener, v0, _lastPremium);
                acc = ctx.vLimit.mul(ctx.t1);
                acc = acc.add(integrateOnFundingCurve(ctx.t1, ctx.t2, v0, _lastPremium));
                acc = acc.add(ctx.vDampener.mul(-ctx.t2));
            } else if (vt <= ctx.vLimit) {
                ctx.t1 = timeOnFundingCurve(ctx.vLimit, v0, _lastPremium);
                acc = ctx.vLimit.mul(ctx.t1);
                acc = acc.add(integrateOnFundingCurve(ctx.t1, n, v0, _lastPremium));
                acc = acc.sub(ctx.vDampener.mul(n));
            } else {
                acc = ctx.vLimit.sub(ctx.vDampener).mul(n);
            }
        }
    } // getAccumulatedFunding
}
