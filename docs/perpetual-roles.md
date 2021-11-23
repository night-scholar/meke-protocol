# Roles

## Traders

The trader first deposits collaterals into the `Perpetual`, then trades with `Exchange` to get his/her positions. 

## Order Book

The off-chain order book matching interface is a supplement to improve the user experience.

Due to the current inefficiency of blockchain, the Hybrid model of off-chain matching and the on-chain transactions is one of the solutions to achieve efficiency.

## Broker

A Broker is an actor who helps trader to accomplish trading. It is a normal ETH address of the order book. The broker is set in the signature of every orders. To receive trading fee, a broker must assign positive maker/taker fee rate in order data structure. And if given a negative trading fee, the broker will pay trader for making / taking order.

## Oracle

Another key component is the decentralized oracle for obtaining the index price (spot price). After extensive research into decentralized oracle solutions, MEKE protocol team unanimously concluded that Chainlink's Price Reference Contracts are the best option in the market for sourcing and securing data. Chainlink already has an ETH/USD Price Reference Contract live on the Ethereum mainnet that is used and supported by several other top DeFi protocols. We are currently leveraging Chainlink's ETH/USD price feed as the index price for the ETH-PERP contract.

## Admin

Admin is a special account who has power to:
* Change the governance parameters
* Upgrade contract
* Global settlement
