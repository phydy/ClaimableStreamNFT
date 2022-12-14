// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface INFT is IERC721 {
    function safeMint(address to) external returns (uint256);
}
