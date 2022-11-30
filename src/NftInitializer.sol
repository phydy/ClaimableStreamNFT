// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;
import {StreamDebtNFT} from "./StreamDebtNFT.sol";
import {IBuss} from "interfaces/IBusiness.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract NftInitializer is Ownable {
    IBuss businessContract;

    constructor(address buss) {
        businessContract = IBuss(buss);
    }

    function initializeNFTContracts() external onlyOwner {
        StreamDebtNFT creditNFT = new StreamDebtNFT("Credit debt NFT", "CDT");
        StreamDebtNFT streamNFT = new StreamDebtNFT("Stream debt NFT", "SDT");
        StreamDebtNFT transferNFT = new StreamDebtNFT(
            "Transfer debt NFT",
            "TDT"
        );
        creditNFT.transferOwnership(address(businessContract));
        streamNFT.transferOwnership(address(businessContract));
        transferNFT.transferOwnership(address(businessContract));
        address[3] memory addresses = [
            address(creditNFT),
            address(transferNFT),
            address(streamNFT)
        ];

        businessContract.addNftAddresses(addresses);
    }
}
