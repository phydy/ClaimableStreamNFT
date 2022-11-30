// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {SuperfluidTester} from "./SuperfluidTester.sol";
import {ISuperToken} from "@superfluid/interfaces/superfluid/ISuperToken.sol";
import {TestToken, IERC20} from "../src/TestToken.sol";
import {ISuperTokenFactory} from "@superfluid/interfaces/superfluid/ISuperTokenFactory.sol";
import {CFAv1Library} from "@superfluid/apps/CFAv1Library.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {StreamDebtNFT} from "../src/StreamDebtNFT.sol";

import {NftInitializer} from "../src/NftInitializer.sol";

import {BusinessContract} from "../src/BusinessContract.sol";

import {INFT} from "interfaces/INFT.sol";

contract TrustFrameworkTest is SuperfluidTester {
    using CFAv1Library for CFAv1Library.InitData;
    address public admin = address(1);
    address public transferlender = address(2);
    address public creditor = address(3);
    address public streamLender = address(4);

    TestToken public testToken;
    ISuperToken public s_testToken;
    ISuperTokenFactory public factory;

    address public host_;
    address public cfa_;
    address public ida_;

    BusinessContract public buss;
    NftInitializer public initi;

    constructor() SuperfluidTester(admin) {}

    function setUp() public {
        vm.startPrank(admin);

        host_ = address(sf.host);
        cfa_ = address(sf.cfa);
        ida_ = address(sf.ida);

        /**
         * initialize the test token
         */
        testToken = new TestToken();

        factory = ISuperTokenFactory(address(sf.superTokenFactory));

        s_testToken = ISuperToken(
            sf.superTokenFactory.createSuperTokenLogic(sf.host)
        );
        s_testToken.initialize(
            IERC20(address(testToken)),
            18,
            "Super Test Trust token",
            "STTT"
        );

        buss = new BusinessContract(sf.host);
        initi = new NftInitializer(address(buss));
        vm.stopPrank();
    }

    function testUpgradeAndDowngrade() public {
        vm.startPrank(admin);
        testToken.approve(address(s_testToken), 1000000 ether);
        ISuperToken(address(s_testToken)).upgrade(1000000 ether);
        assert(
            ISuperToken(address(s_testToken)).balanceOf(admin) == 1000000 ether
        );
        vm.stopPrank();
    }

    function testInitializeNFT() public {
        vm.startPrank(admin);
        initi.initializeNFTContracts();
        vm.stopPrank();
    }

    /**
     * we will attemp a workflow of the project.
     * ie: start from when the business broadcast's a credit need to all types of users claiming
     */
    function testBusiness() public {
        //we add an asset
        vm.startPrank(admin);

        //ninitalize nfts
        initi.initializeNFTContracts();

        //add asset
        buss.addAsset(
            testToken.symbol(),
            address(testToken),
            address(46475),
            address(s_testToken)
        );

        (address token, address agg, address stoken) = buss.assetInformation(
            testToken.symbol()
        );

        //check that the asset information was addres correctly
        assert(token == address(testToken));
        assert(agg == address(46475));
        assert(stoken == address(s_testToken));

        // create a credit broadcast to allow people to lend for a claimable NFT stream
        buss.broadcastCredit(
            testToken.symbol(),
            1000000 ether,
            10000000000000000000,
            90 days,
            50
        );

        assert(buss.creditRound() == 1);

        (
            ,
            uint256 tranfa,
            int96 fr,
            uint256 duration,
            uint256 percentage
        ) = buss.creditNeeded(buss.creditRound());

        //assert the broadcasted information
        assert(tranfa == 1000000 ether);
        assert(fr == 10000000000000000000);
        assert(duration == 90 days);
        assert(percentage == 50);

        //Provide Funds For an NFT with a claimable stram
        testToken.approve(address(s_testToken), 1000000 ether);
        ISuperToken(address(s_testToken)).upgrade(1000000 ether);
        //get tokens
        s_testToken.transfer(transferlender, 10000 ether);

        assert(s_testToken.balanceOf(transferlender) == 10000 ether);

        vm.stopPrank();

        vm.startPrank(transferlender);

        s_testToken.approve(address(buss), 9000 ether);

        //Lend to the Business for an NFT with a claimable stream
        uint256 id = buss.lendToBusiness(9000 ether);
        console.log(id);

        assert(id == 1);
        vm.stopPrank();

        vm.startPrank(admin);
        s_testToken.transfer(streamLender, 50000 ether);
        assert(s_testToken.balanceOf(streamLender) == 50000 ether);
        vm.stopPrank();

        //open a stream to the Business contract to receive an NFT
        vm.startPrank(streamLender);
        bytes memory _userData = abi.encodeCall(
            sf.cfa.createFlow,
            (s_testToken, address(buss), 0.05 ether, new bytes(0))
        );

        sf.host.callAgreement(sf.cfa, _userData, new bytes(0));

        vm.stopPrank();

        INFT streamNFT = buss.streamDebNFT();

        assert(streamNFT.ownerOf(1) == streamLender);

        //offer a service provider an NFT to claim a stream later

        vm.startPrank(admin);
        buss.giveClaimableNFT(address(s_testToken), creditor, 15000 ether);
        vm.stopPrank();
        INFT creditNFT = buss.creditDebNFT();

        assert(creditNFT.ownerOf(1) == creditor);

        //startClaiming Streams with respective nfts
        vm.warp(block.timestamp + 90 days);
        vm.roll(10000);

        vm.startPrank(streamLender);
        bytes memory userData_ = abi.encodeCall(
            sf.cfa.deleteFlow,
            (s_testToken, streamLender, address(buss), new bytes(0))
        );

        sf.host.callAgreement(sf.cfa, userData_, new bytes(0));

        uint256 id_ = buss.tokenAddressStreamNftId(
            address(s_testToken),
            streamLender
        );
        //Claim your stream with an nft
        //this is for the indivual who provided funds using streams
        buss.claimStream(id_, 13847463532);

        vm.stopPrank();
    }
}
