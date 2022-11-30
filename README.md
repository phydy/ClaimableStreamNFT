# **NFTs that give claim to a stream**.

This project will showcase an implementation of an NFT that gives the holder the power to claim
to claim a stream.

The sample will be based on a business setting where the contract can generate NFTs to clients, creditors or employees who can claim
their streams when a predetermined time comes.

## Project Breakdown

### Hyposesis

Business A operates onchain, It interacts with stakeholders like Creditors, Freelancers and Customers.

The Business pays its employees in streams.

It also accepts credit through streams and also thorugh normal ERC20 transfers.

Any credit offered to the Business is represented in an NFT. Which gets burned when the stream is claimed

#### Business Revenue

The business generates its revenue through its clients and creditors

It also acquires some services on credit

The revenue gets distributed to its expenses through streams.

**Salaries**

Streamed every moment to its employees

**Debts**

Streamed after a period of time

### implementation

We first write the Business Contract to handle the process of borrowing, and issueing NFTs as a claim for future stream allocation
