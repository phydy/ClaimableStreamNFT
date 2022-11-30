// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {INFT} from "interfaces/INFT.sol";

import {ISuperfluid, ISuperToken, ISuperfluidToken, ISuperApp, ISuperAgreement, SuperAppDefinitions} from "@superfluid/interfaces/superfluid/ISuperfluid.sol";

import {CFAv1Library} from "@superfluid/apps/CFAv1Library.sol";

import {IConstantFlowAgreementV1} from "@superfluid/interfaces/agreements/IConstantFlowAgreementV1.sol";

import {SuperAppBase} from "@superfluid/apps/SuperAppBase.sol";

/// @dev Constant Flow Agreement registration key, used to get the address from the host.
bytes32 constant CFA_ID = keccak256(
    "org.superfluid-finance.agreements.ConstantFlowAgreement.v1"
);

/// @dev Thrown when the receiver is the zero adress.
error InvalidReceiver();

/// @dev Thrown when receiver is also a super app.
error ReceiverIsSuperApp();

/// @dev Thrown when the callback caller is not the host.
error Unauthorized();

/// @dev Thrown when the token being streamed to this contract is invalid
error InvalidToken();

/// @dev Thrown when the agreement is other than the Constant Flow Agreement V1
error InvalidAgreement();

//ERC20 transfer fail
error TransferFailed();

contract BusinessContract is Ownable, SuperAppBase {
    ISuperfluid private _host; // host
    IConstantFlowAgreementV1 private _cfa;
    //Debt NFT contract interface
    INFT public creditDebNFT;
    INFT public transferDebNFT;
    INFT public streamDebNFT;

    //structure of an asset: ie address, agrregator, and superTokenAddress
    struct Asset {
        address assetAddress;
        address aggregatorAddress;
        address superTokenAddress;
    }
    // asset aggregator addresses maped to the asset string
    mapping(string => Asset) public assetInformation;

    //maps an Id to the close Timestamp
    mapping(uint256 => uint256) public idCreditCloseTimestamp;

    mapping(uint256 => uint256) public idTransferCloseTimestamp;

    mapping(uint256 => uint256) public idStreamCloseTimestamp;

    /**
     * enum to show different ways the company takes debts
     * stream: any credit give through streams
     * trensfer: Any credit give through ERC20 transfer
     * credit_services: any credit owed due to services rendered or good delivered
     */
    enum DEBT_TYPE {
        STREAM,
        TRANSFER,
        CREDIT_SERVICES
    }

    /**
     * struct for showing the Debt information
     */

    struct DebtInfo {
        address token;
        DEBT_TYPE dType;
        uint256 amount;
        uint256 percentage;
        uint256 startTime;
        uint256 claimDate;
        int96 flowRate;
    }

    /**
     * shows how much credit is required by the business,
     * transferables: the amount that can get transfered
     * flowrate: the maximum flowrate required
     */

    struct CreditBroadcast {
        string asset;
        uint256 transferables;
        int96 flowRate;
        uint256 duration;
        uint256 percentageIntrest;
    }

    /**
     * map the current credit round to the Broadcast info
     */

    mapping(uint256 => CreditBroadcast) public creditNeeded;

    /**
     * current credit Round
     */
    uint256 public creditRound;

    //uint256 public currentPercentage;
    /**
     * map a debt struct to a transfer NFT ID
     */

    mapping(uint256 => DebtInfo) public idToInfo;

    /**
     * maps debt struct to credit bft
     */

    mapping(uint256 => DebtInfo) public idToCreditInfo;

    /**
     * debt struct maped to a stream debt nft
     */
    mapping(uint256 => DebtInfo) public idToStreamInfo;

    /**
     * map a superToken to an address and NFT ID
     */

    mapping(address => mapping(address => uint256)) public tokenAddressNftId;

    /**
     * map nfts to indidual creditors
     */

    mapping(address => mapping(address => uint256))
        public tokenAddressCreditNftId;

    /**
     * track nfts given by indivuals lending through a stream
     */
    mapping(address => mapping(address => uint256))
        public tokenAddressStreamNftId;

    modifier onlyHost() {
        if (msg.sender != address(_host)) revert Unauthorized();
        _;
    }

    modifier onlyExpected(address agreementClass) {
        if (agreementClass != address(_cfa)) revert InvalidAgreement();
        _;
    }

    event NftIssued(
        address indexed user,
        DEBT_TYPE indexed reason,
        uint256 claimDate_
    );

    event CreaditBroadcasted(string indexed asset_, uint256 indexed interest_);

    /**
     * nft_: nft address
     */
    constructor(ISuperfluid host) {
        _host = host;
        _cfa = IConstantFlowAgreementV1(
            address(host.getAgreementClass(CFA_ID))
        );

        // Registers Super App, indicating it is the final level (it cannot stream to other super
        // apps), and that the `before*` callbacks should not be called on this contract, only the
        // `after*` callbacks.
        _host.registerApp(
            SuperAppDefinitions.APP_LEVEL_FINAL |
                SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP |
                SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP |
                SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP
        );
    }

    /**
     * broadcast credit to the masses
     */
    function broadcastCredit(
        string memory asset_,
        uint256 transferables_,
        int96 flowRate_,
        uint256 duration_,
        uint256 interest_
    ) external onlyOwner {
        uint256 _creditRound = creditRound + 1;

        creditNeeded[_creditRound] = CreditBroadcast({
            asset: asset_,
            transferables: transferables_,
            flowRate: flowRate_,
            duration: duration_,
            percentageIntrest: interest_
        });

        creditRound += 1;

        emit CreaditBroadcasted(asset_, interest_);
    }

    //Add an asset to the platform
    function addAsset(
        string memory _asset,
        address _assetAddress,
        address _aggregatorAddress,
        address sTAddress
    ) external onlyOwner {
        assetInformation[_asset] = Asset({
            assetAddress: _assetAddress,
            aggregatorAddress: _aggregatorAddress,
            superTokenAddress: sTAddress
        });
    }

    //get the price of an asset
    //function getPrice(string memory _asset) external view returns (int256) {
    //    (, int256 price, , , ) = AggregatorV3Interface(
    //        assetInformation[_asset].aggregatorAddress
    //    ).latestRoundData();
    //    return price;
    //}

    /**
     * user lends to the business to receive an NFT that gives him a claim to a future stream
     */
    function lendToBusiness(uint256 _amount) external returns (uint256 id) {
        uint256 round = creditRound;
        require(round != 0, "wrong round");
        CreditBroadcast memory credit = creditNeeded[round];
        require(credit.transferables != 0, "cant lend");
        require(_amount <= credit.transferables, "need less");
        uint256 duration = credit.duration;

        uint256 _time = (block.timestamp + duration);
        string memory _asset = credit.asset;
        Asset memory asset = assetInformation[_asset];
        IERC20 token = IERC20(asset.superTokenAddress);
        bool success = token.transferFrom(msg.sender, address(this), _amount);
        if (!success) {
            revert TransferFailed();
        } else {
            uint256 checked_id = tokenAddressNftId[asset.superTokenAddress][
                msg.sender
            ];
            DebtInfo memory debt = idToInfo[checked_id];
            if (debt.token == address(0)) {
                id = mintTransferNFT(msg.sender);
                idToInfo[id] = DebtInfo({
                    token: asset.superTokenAddress,
                    dType: DEBT_TYPE.TRANSFER,
                    amount: _amount,
                    percentage: credit.percentageIntrest,
                    startTime: block.timestamp,
                    claimDate: _time,
                    flowRate: 0
                });
                tokenAddressNftId[asset.superTokenAddress][msg.sender] = id;

                emit NftIssued(msg.sender, DEBT_TYPE.CREDIT_SERVICES, _time);
            } else {
                idToInfo[checked_id] = DebtInfo({
                    token: asset.superTokenAddress,
                    dType: DEBT_TYPE.TRANSFER,
                    amount: (debt.amount + _amount),
                    percentage: credit.percentageIntrest,
                    startTime: debt.startTime,
                    claimDate: debt.claimDate,
                    flowRate: 0
                });

                emit NftIssued(msg.sender, DEBT_TYPE.CREDIT_SERVICES, _time);
            }
        }
        creditNeeded[round].transferables -= _amount;
    }

    /**
     * The business offers a claimable NFT to a user (service provider, goods on credit..) to claim a stream in future
     */
    function giveClaimableNFT(
        address _token,
        address _receiver,
        uint256 amountOwed
    ) external onlyOwner {
        uint256 round = creditRound;
        require(round != 0, "wrong round");
        CreditBroadcast memory credit = creditNeeded[round];
        require(amountOwed <= credit.transferables, "need less");
        uint256 _claimDate = credit.duration;
        uint256 checking_id = tokenAddressCreditNftId[_token][_receiver];
        DebtInfo memory debt = idToCreditInfo[checking_id];
        uint256 _time = (block.timestamp + _claimDate);
        if (debt.token == address(0)) {
            uint256 id = mintCreditNFT(_receiver);

            idToCreditInfo[id] = DebtInfo({
                token: _token,
                dType: DEBT_TYPE.CREDIT_SERVICES,
                amount: amountOwed,
                percentage: credit.percentageIntrest,
                startTime: block.timestamp,
                claimDate: _time,
                flowRate: 0
            });

            tokenAddressCreditNftId[_token][_receiver] = id;
            emit NftIssued(_receiver, DEBT_TYPE.CREDIT_SERVICES, _time);
        } else {
            idToCreditInfo[checking_id] = DebtInfo({
                token: _token,
                dType: DEBT_TYPE.CREDIT_SERVICES,
                amount: (debt.amount + amountOwed),
                percentage: credit.percentageIntrest,
                startTime: block.timestamp,
                claimDate: _time,
                flowRate: 0
            });

            emit NftIssued(_receiver, DEBT_TYPE.CREDIT_SERVICES, _time);
        }
    }

    function createFlow(
        address token,
        address receiver_,
        int96 _flowRate
    ) public {
        _host.callAgreement(
            _cfa,
            abi.encodeWithSelector(
                _cfa.createFlow.selector,
                ISuperToken(token),
                receiver_,
                _flowRate,
                new bytes(0) // placeholder
            ),
            "0x"
        );
    }

    /**
     * claim a stream from a streamed credit
     */
    function claimStream(uint256 nftId) external {
        DebtInfo memory debt = idToStreamInfo[nftId];
        require(block.timestamp >= debt.claimDate, "not yet time");
        uint256 id_confirmation = tokenAddressStreamNftId[debt.token][
            msg.sender
        ];
        require(nftId == id_confirmation, "wrong token");

        //uint256 fr = ;//(debt.amount + ((debt.percentage * 1000) / 100)) / 90 days;

        int96 flowrate = debt.flowRate; //int96(int256(fr));

        createFlow(debt.token, msg.sender, 19273263748473);
    }

    /**
     * claim astream from a trnsfer credit
     */
    function claimTransferStream(uint256 nftId) external {
        DebtInfo memory debt = idToInfo[nftId];
        require(block.timestamp >= debt.claimDate, "not yet time");
        uint256 id_confirmation = tokenAddressNftId[debt.token][msg.sender];
        require(nftId == id_confirmation, "wrong token");

        uint256 fr = (debt.amount + ((debt.percentage / 1000) * 100)) / 90 days;

        int96 flowrate = int96(int256(fr));

        createFlow(debt.token, msg.sender, flowrate);
    }

    /**
     * claim a stream from a service credit
     */
    function claimCreditStream(uint256 nftId) external {
        DebtInfo memory debt = idToCreditInfo[nftId];
        require(block.timestamp >= debt.claimDate, "not yet time");
        uint256 id_confirmation = tokenAddressCreditNftId[debt.token][
            msg.sender
        ];
        require(nftId == id_confirmation, "wrong token");

        uint256 fr = (debt.amount + ((debt.percentage * 1000) / 100)) / 90 days;

        int96 flowrate = int96(int256(fr));

        createFlow(debt.token, msg.sender, flowrate);

        idStreamCloseTimestamp[nftId] = block.timestamp + 90 days;
    }

    function addNftAddresses(address[3] memory addresses) external {
        require(address(creditDebNFT) == address(0), "already addred");
        creditDebNFT = INFT(addresses[0]);
        transferDebNFT = INFT(addresses[1]);
        streamDebNFT = INFT(addresses[2]);
    }

    /**
     * mint an nft to an address
     */
    function mintCreditNFT(address receiver) private returns (uint256) {
        uint256 id = creditDebNFT.safeMint(receiver);
        return id;
    }

    function mintTransferNFT(address receiver) private returns (uint256) {
        uint256 id = transferDebNFT.safeMint(receiver);
        return id;
    }

    function mintStreamNFT(address receiver) private returns (uint256) {
        uint256 id = streamDebNFT.safeMint(receiver);
        return id;
    }

    /**
     * get the encoded user data
     */
    function getUserNewStreamData(uint256 amountExpectedToFlow)
        external
        pure
        returns (bytes memory data)
    {
        data = abi.encode(amountExpectedToFlow);
    }

    /**
     * get an address' flow rate
     */
    function getFlowRate(address token, address sender_)
        internal
        view
        returns (int96 fr)
    {
        (, fr, , ) = _cfa.getFlow(ISuperToken(token), sender_, address(this));
    }

    /**
     * updates the state of the contract after a new flow by a user is created
     */
    function updateCreate(bytes calldata ctx, address _superToken)
        private
        returns (bytes memory newCtx)
    {
        newCtx = ctx;
        uint256 round = creditRound;
        CreditBroadcast memory credit = creditNeeded[round];
        ISuperfluid.Context memory dContext = _host.decodeCtx(ctx);
        address sender = dContext.msgSender;
        int96 userInflow = getFlowRate(_superToken, sender);
        uint256 amount_ = (uint256(int256(userInflow)) * credit.duration); //abi.decode(dContext.userData, (uint256));
        //if (credit.flowRate < userInflow) {
        //    return "";
        //}
        uint256 _claimDate = credit.duration + block.timestamp;
        uint256 id = mintStreamNFT(sender);
        idToStreamInfo[id] = DebtInfo({
            token: _superToken,
            dType: DEBT_TYPE.STREAM,
            amount: amount_,
            percentage: credit.percentageIntrest,
            startTime: block.timestamp,
            claimDate: _claimDate,
            flowRate: userInflow
        });
        tokenAddressStreamNftId[_superToken][msg.sender] = id;

        emit NftIssued(msg.sender, DEBT_TYPE.CREDIT_SERVICES, 0);
    }

    /**
     * updates the state of the contract after an Update to a flow by a user is made
     */
    function updateUpdate(bytes calldata ctx, address _superToken)
        private
        returns (bytes memory newCtx)
    {
        newCtx = ctx;
        uint256 round = creditRound;
        CreditBroadcast memory credit = creditNeeded[round];
        ISuperfluid.Context memory dContext = _host.decodeCtx(ctx);
        address sender = dContext.msgSender;
        int96 userInflow = getFlowRate(_superToken, sender);
        require(userInflow <= credit.flowRate, "much flow");

        uint256 nft_id = tokenAddressStreamNftId[_superToken][sender];

        DebtInfo memory debt = idToStreamInfo[nft_id];

        uint256 amount_ = (uint256(int256(userInflow)) *
            credit.duration -
            (block.timestamp - debt.startTime)); //abi.decode(dContext.userData, (uint256));
        uint256 accumulated = uint256(int256(debt.flowRate)) *
            (block.timestamp - debt.startTime);
        uint256 total = amount_ + accumulated;

        idToStreamInfo[nft_id] = DebtInfo({
            token: _superToken,
            dType: DEBT_TYPE.STREAM,
            amount: total,
            percentage: credit.percentageIntrest,
            startTime: block.timestamp,
            claimDate: debt.claimDate,
            flowRate: userInflow
        });
    }

    function updateTerminate(bytes calldata ctx, address _superToken)
        private
        returns (bytes memory newCtx)
    {
        newCtx = ctx;
        ISuperfluid.Context memory dContext = _host.decodeCtx(ctx);
        address sender = dContext.msgSender;
        uint256 nft_id = tokenAddressNftId[_superToken][sender];

        DebtInfo memory debt = idToStreamInfo[nft_id];
        uint256 accumulated = uint256(int256(debt.flowRate)) *
            (block.timestamp - debt.startTime);
        idToStreamInfo[nft_id] = DebtInfo({
            token: _superToken,
            dType: DEBT_TYPE.STREAM,
            amount: accumulated,
            percentage: debt.percentage,
            startTime: debt.startTime,
            claimDate: debt.claimDate,
            flowRate: debt.flowRate
        });
    }

    // ---------------------------------------------------------------------------------------------
    // SUPER APP CALLBACKS
    function beforeAgreementCreated(
        ISuperToken, /*superToken*/
        address, /*agreementClass*/
        bytes32, /*agreementId*/
        bytes calldata, /*agreementData*/
        bytes calldata /*_ctx*/
    )
        external
        view
        virtual
        override
        returns (
            bytes memory /*cbdata*/
        )
    {
        if (creditRound == 0) {
            revert("wrong round");
        }
    }

    function afterAgreementCreated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32, //_agreementId
        bytes calldata, //_agreementData
        bytes calldata, //_cbdata
        bytes calldata _ctx
    )
        external
        override
        onlyExpected(_agreementClass)
        onlyHost
        returns (bytes memory newCtx)
    {
        newCtx = updateCreate(_ctx, address(_superToken));
    }

    function afterAgreementUpdated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32, // _agreementId,
        bytes calldata, // _agreementData,
        bytes calldata, // _cbdata,
        bytes calldata _ctx
    )
        external
        override
        onlyExpected(_agreementClass)
        onlyHost
        returns (bytes memory newCtx)
    {
        return updateUpdate(_ctx, address(_superToken));
    }

    function afterAgreementTerminated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32, // _agreementId,
        bytes calldata, // _agreementData
        bytes calldata, // _cbdata,
        bytes calldata _ctx
    ) external override onlyHost returns (bytes memory newCtx) {
        // According to the app basic law, we should never revert in a termination callback
        if (_agreementClass != address(_cfa)) {
            return _ctx;
        }
        return updateTerminate(_ctx, address(_superToken));
    }
}
