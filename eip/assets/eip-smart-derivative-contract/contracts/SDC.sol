// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "./ISDC.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract SDC is ISDC {
    /*
     * Trade States
     */
        enum TradeState {

        /*
         * State before the trade is incepted.
         */
        Inactive,

        /*
         * Incepted: Trade data submitted by one party. Market data for initial valuation is set.
         */
        Incepted,

        /*
         * Confirmed: Trade data accepted by other party.
         */
        Confirmed,

        /*
         * Active (Confirmend + Prefunded Termination Fees). Will cycle through process states.
         */
        Active,

        /*
         * Terminated.
         */
        Terminated
    }

    /*
     * Process States
     */
    enum ProcessState {
        Idle,
        Initiation,
        Funding,
        MarginAccountCheck,
        MarginAccountLocked,
        ValuationAndSettlement,
        Settled,
        InTermination
    }

    struct MarginRequirement {
        int256 buffer;
        int256 terminationFee;
    }

    /*
     * Modifiers serve as guards whether at a specific process state a specific function can be called
     */

    modifier onlyCounterparty() {
        require(msg.sender == party1 || msg.sender == party2, "You are not a counterparty.");
        _;
    }

    TradeState private tradeState;
    ProcessState private processState;

    address public party1;
    address public party2;
    address private immutable receivingPartyAddress; // Determine the receiver: Positive values are consider to be received by receivingPartyAddress. Negative values are received by the other counterparty.

    /*
     * liquidityToken holds:
     * - funding account of party1
     * - funding account of party2
     * - account for SDC (sum - this is split among parties by sdcBalances)
     */
    IERC20 private liquidityToken;

    string private tradeID;
    string private tradeData;

    mapping(address => MarginRequirement) private marginRequirements; // Storage of M and P per counterparty address
    mapping(uint256 => address) private pendingRequests; // Stores open request hashes for several requests: initiation, update and termination

    mapping(address => int256) private sdcBalances; // internal book-keeping: needed to track what part of the gross token balance is held for each party


    bool private mutuallyTerminated = false;

    constructor(
        address counterparty1,
        address counterparty2,
        address receivingParty,
        address tokenAddress,
        uint256 initialMarginRequirement,
        uint256 initalTerminationFee
    ) {
        party1 = counterparty1;
        party2 = counterparty2;
        receivingPartyAddress = receivingParty;
        liquidityToken = IERC20(tokenAddress);
        tradeState = TradeState.Inactive;
        processState = ProcessState.Idle;
        marginRequirements[party1] = MarginRequirement(int256(initialMarginRequirement), int256(initalTerminationFee));
        marginRequirements[party2] = MarginRequirement(int256(initialMarginRequirement), int256(initalTerminationFee));
        sdcBalances[party1] = 0;
        sdcBalances[party2] = 0;
    }

    /*
     * generates a hash from tradeData and generates a map entry in openRequests
     * emits a TradeInceptedEvent
     */
    function inceptTrade(string memory _tradeData) external override onlyCounterparty
    {
        processState = ProcessState.Initiation;
        tradeState = TradeState.Incepted; // Set TradeState to Incepted

        uint256 hash = uint256(keccak256(abi.encode(_tradeData)));
        pendingRequests[hash] = msg.sender;
        tradeID = Strings.toString(hash);
        tradeData = _tradeData; // Set Trade Data to enable querying already in inception state

        emit TradeInceptedEvent(msg.sender, tradeID, _tradeData);
    }

    /*
     * generates a hash from tradeData and checks whether an open request can be found by the opposite party
     * if so, data are stored and open request is deleted
     * emits a TradeConfirmedEvent
     */
    function confirmTrade(string memory _tradeData) external override onlyCounterparty
    {
        address pendingRequestParty = msg.sender == party1 ? party2 : party1;
        uint256 tradeIDConf = uint256(keccak256(abi.encode(_tradeData)));
        require(pendingRequests[tradeIDConf] == pendingRequestParty, "Confirmation fails due to inconsistent trade data or wrong party address");
        delete pendingRequests[tradeIDConf]; // Delete Pending Request

        tradeState = TradeState.Confirmed;
        emit TradeConfirmedEvent(msg.sender, tradeID); // subscribe event und handler, h löst tx aus gegen token

        // Pre-Conditions
        _lockTerminationFees();

        processState = ProcessState.Funding;
        emit MarginAccountUnlockedEvent();
    }

    /**
     * TODO Possible improvement: first check approvals for both parties, then transfer.
     */
    function _lockTerminationFees() internal {
        try liquidityToken.transferFrom(party1, address(this), uint(marginRequirements[party1].terminationFee)) {
        } catch Error(string memory reason) {
            tradeState = TradeState.Inactive;
            processState = ProcessState.Idle;
            emit TerminationEvent("Termination Fee could not be locked from party 1.");
            return;
        }
        try liquidityToken.transferFrom(party2, address(this),uint(marginRequirements[party2].terminationFee)) {
        }  catch Error(string memory reason) {
            // Revert Party 1 Termination Free
            liquidityToken.transferFrom(address(this), party1, uint(marginRequirements[party1].terminationFee));

            tradeState == TradeState.Inactive;
            processState = ProcessState.Idle;
            emit TerminationEvent("Termination Fee could not be locked from party 2.");
            return;
        }
        adjustSDCBalances(marginRequirements[party1].terminationFee, marginRequirements[party2].terminationFee); // Update internal balances
    }

    /*
     * Failsafe: Free up accounts upon termination
     */
    function _processTermination() internal {
        liquidityToken.transferFrom(address(this), party1, uint256(sdcBalances[party1]));
        liquidityToken.transferFrom(address(this), party2, uint256(sdcBalances[party1]));

        processState = ProcessState.Idle;
        tradeState = TradeState.Inactive;
    }

    /*
     * Settlement Cycle
     */

    /*
     * Send an Lock Request Event only when Process State = Funding
     * Puts Process state to Margin Account Check
     */
    function ensurePrefunding() external override {
        processState = ProcessState.MarginAccountCheck;

        uint256 balance1 = liquidityToken.balanceOf(party1);
        uint256 balance2 = liquidityToken.balanceOf(party2);
        _ensurePrefunding(balance1, balance2);
    }


    /*
     * Only when State = MarginAccountCheck
     * Checks balances for each party and sends PaymentRequest on Termination
     * If successfull checked TradeState is put to Active, ProcessState is put to MarginAccountLocked
     * TODO REMOVE - call back can be realized in liquidityToken
     */
//    function performMarginAccountCheck(uint256 balanceParty1, uint256 balanceParty2) external override  {
//        _processMarginLock(balanceParty1, balanceParty2);
//    }

    function _ensurePrefunding(uint balanceParty1, uint balanceParty2) internal {
        /* Calculate gap amount for each party, i.e. residual between buffer and termination fee and actual balance */
        // max(M+P - sdcBalance,0)
        uint gapAmountParty1 = marginRequirements[party1].buffer + marginRequirements[party1].terminationFee - sdcBalances[party1] > 0 ? uint(marginRequirements[party1].buffer + marginRequirements[party1].terminationFee - sdcBalances[party1]) : 0;
        uint gapAmountParty2 = marginRequirements[party2].buffer + marginRequirements[party2].terminationFee - sdcBalances[party2] > 0 ? uint(marginRequirements[party2].buffer + marginRequirements[party2].terminationFee - sdcBalances[party2]) : 0;

        /* Good case: Balances are sufficient and token has enough approval */
        if ( (balanceParty1 >= gapAmountParty1 && liquidityToken.allowance(party1,address(this)) >= gapAmountParty1) &&
            (balanceParty2 >= gapAmountParty2 && liquidityToken.allowance(party2,address(this)) >= gapAmountParty2) ) {
            liquidityToken.transferFrom(party1, address(this), gapAmountParty1);  // Transfer of GapAmount to sdc contract
            liquidityToken.transferFrom(party2, address(this), gapAmountParty2);  // Transfer of GapAmount to sdc contract
            tradeState = TradeState.Active;
            processState = ProcessState.MarginAccountLocked;
            adjustSDCBalances(int(gapAmountParty1),int(gapAmountParty2));  // Update internal balances
            emit MarginAccountLockedEvent();
            emit TradeActivatedEvent(tradeID);
        }
        /* Party 1 - Bad case: Balances are insufficient or token has not enough approval */
        else if ( (balanceParty1 < gapAmountParty1 || liquidityToken.allowance(party1,address(this)) < gapAmountParty1) &&
            (balanceParty2 >= gapAmountParty2 && liquidityToken.allowance(party2,address(this)) >= gapAmountParty2) ) {
            tradeState = TradeState.Terminated;
            processState = ProcessState.InTermination;

            adjustSDCBalances(-marginRequirements[party1].terminationFee,marginRequirements[party1].terminationFee); // Update internal balances

            _processTermination(); // Release all buffers
            emit TerminationEvent("Termination caused by party1 due to insufficient prefunding");
        }
        /* Party 2 - Bad case: Balances are insufficient or token has not enough approval */
        else if ( (balanceParty1 >= gapAmountParty1 && liquidityToken.allowance(party1,address(this)) >= gapAmountParty1) &&
            (balanceParty2 < gapAmountParty2 || liquidityToken.allowance(party2,address(this)) < gapAmountParty2) ) {
            tradeState = TradeState.Terminated;
            processState = ProcessState.InTermination;

            adjustSDCBalances(marginRequirements[party2].terminationFee,-marginRequirements[party2].terminationFee); // Update internal balances

            _processTermination(); // Release all buffers
            emit TerminationEvent("Termination caused by party2 due to insufficient prefunding");
        }
        /* Both parties fail: Cross Transfer of Termination Fee */
        else {
            tradeState = TradeState.Terminated;
            processState = ProcessState.InTermination;
            // if ( (balanceParty1 < gapAmountParty1 || liquidityToken.allowance(party1,address(this)) < gapAmountParty1) &&  (balanceParty2 < gapAmountParty2 || liquidityToken.allowance(party2,address(this)) < gapAmountParty2) ) { tradeState = TradeState.Terminated;
            adjustSDCBalances(marginRequirements[party2].terminationFee-marginRequirements[party1].terminationFee,marginRequirements[party1].terminationFee-marginRequirements[party2].terminationFee); // Update internal balances: Cross Booking of termination fee

            _processTermination(); // Release all buffers
            emit TerminationEvent("Termination caused by both parties due to insufficient prefunding");
        }
    }

    /*
     * Settlement can be initiated when margin accounts are locked, a valuation request event is emitted containing tradeData and valuationViewParty
     * Changes Process State to Valuation&Settlement
     */
    function initiateSettlement() external override onlyCounterparty
    {
        processState = ProcessState.ValuationAndSettlement;
        emit ValuationRequestEvent(tradeData);
    }

    /*
     * Performs a settelement only when processState is ValuationAndSettlement
     * Puts process state to "inTransfer"
     * Checks Settlement amount according to valuationViewParty: If SettlementAmount is > 0, valuationViewParty receives
     */
    function performSettlement(int256 settlementAmount, string memory marketData) external override
    {
        int256 transferAmount = abs(settlementAmount);

        address receivingParty  = settlementAmount > 0 ? receivingPartyAddress : other(receivingPartyAddress);
        address payingParty     = other(receivingParty);

        if (transferAmount > marginRequirements[payingParty].buffer) {   // Termination Event, buffer not sufficient
            tradeState = TradeState.Terminated;
            transferAmount = marginRequirements[payingParty].buffer + marginRequirements[payingParty].terminationFee; // Override with Buffer and Termination Fee: Max Transfer

            if(receivingParty == party1) {
                adjustSDCBalances(transferAmount, -transferAmount);
            }
            else {
                adjustSDCBalances(-transferAmount, transferAmount);
            }

            _processTermination(); // Transfer
            emit TerminationEvent("Termination due to margin buffer exceedance");
        } else {   // Regular Settlement
            if(payingParty == party1) {
                adjustSDCBalances(-transferAmount,0);
            }
            else {
                adjustSDCBalances(0,-transferAmount);
            }
            liquidityToken.transfer(receivingParty, uint256(transferAmount)); // SDC Contract performs transfer to receiving party
            processState = ProcessState.Settled;  // Set Process State to Settled

            emit SettlementCompletedEvent();
        }

        if (mutuallyTerminated) {
            tradeState = TradeState.Terminated;
        }
    }

    /*
     * End of Cycle
     *
     /

    /*
     * Can be called by a party for mutual termination
     * Hash is generated an entry is put into pendingRequests
     * TerminationRequest is emitted
     */
    function requestTradeTermination(string memory _tradeID) external override onlyCounterparty
    {
        require(keccak256(abi.encodePacked(tradeID)) == keccak256(abi.encodePacked(_tradeID)), "Trade ID mismatch");
        uint256 hash = uint256(keccak256(abi.encode(_tradeID, "terminate")));
        pendingRequests[hash] = msg.sender;
        emit TerminationRequestEvent(msg.sender, _tradeID);
    }

    /*

     * Same pattern as for initiation
     * confirming party generates same hash, looks into pendingRequests, if entry is found with correct address, tradeState is put to terminated
     */
    function confirmTradeTermination(string memory tradeId) external override onlyCounterparty
    {
        address pendingRequestParty = msg.sender == party1 ? party2 : party1;
        uint256 hashConfirm = uint256(keccak256(abi.encode(tradeId, "terminate")));
        require(pendingRequests[hashConfirm] == pendingRequestParty, "Confirmation of termination failed due to wrong party or missing request");
        delete pendingRequests[hashConfirm];
        mutuallyTerminated = true;
        emit TerminationConfirmedEvent(msg.sender, tradeID);
    }

    function initiateMarginReqirementUpdate() external override {
        emit MarginRequirementUpdateRequestEvent();
    }

    function performMarginRequirementUpdate(address _address, uint256 amount) external override
    {
        marginRequirements[_address].buffer = int256(amount);
        emit MarginRequirementUpdatedEvent();
    }

    function adjustSDCBalances(int256 adjustmentAmountParty1, int256 adjustmentAmountParty2) internal {
        if (adjustmentAmountParty1 < 0)
            require(sdcBalances[party1] >= adjustmentAmountParty1, "SDC Balance Adjustment fails for Party1");
        if (adjustmentAmountParty2 < 0)
            require(sdcBalances[party2] >= adjustmentAmountParty2, "SDC Balance Adjustment fails for Party2");
        sdcBalances[party1] = sdcBalances[party1] + adjustmentAmountParty1;
        sdcBalances[party2] = sdcBalances[party2] + adjustmentAmountParty2;
    }

    /*
     * Utilities
     */

    /**
     * Absolute value of an integer
     */
    function abs(int x) private pure returns (int) {
        return x >= 0 ? x : -x;
    }

    /**
     * Other party
     */
    function other(address party) private pure returns (address) {
        return (party == party1 ? party2 : party1);
    }

    function getTokenAddress() public view returns(address) {
        return address(liquidityToken);
    }

    function getTradeID() public view returns (string memory) {
        return tradeID;
    }

    function getTradeData() public view returns (string memory) {
        return tradeData;
    }


    function getTradeState() public view returns (TradeState) {
        return tradeState;
    }

    function getProcessState() public view returns (ProcessState) {
        return processState;
    }

    function getOwnSdcBalance() public view returns (int256) {
        return sdcBalances[msg.sender];
    }

    /**END OF FUNCTIONS WHICH ARE ONLY USED FOR TESTING PURPOSES */
}



/**
 modifier onlyWhenInactive() {
        require(
            tradeState == TradeState.Inactive,
            "Trade state is not 'Inactive'."
        );
        _;
    }
    modifier onlyWhenIdle() {
        require(
            processState == ProcessState.Idle,
            "Process state is not 'Idle'."
        );
        _;
    }

    modifier onlyWhenIncepted() {
        require(
            tradeState == TradeState.Incepted,
            "Trade state is not 'Incepted'."
        );
        _;
    }

    modifier onlyWhenConfirmedOrSettled() {
        require(
            (tradeState == TradeState.Confirmed) ||
            (tradeState == TradeState.Active &&
            processState == ProcessState.Settled),
            "Trade state is not 'Initiated' or 'Settled'."
        );
        _;
    }

    modifier onlyWhenConfirmedOrSettledOrTerminated() {
        require(
            (tradeState == TradeState.Confirmed) ||
            (tradeState == TradeState.Active && processState == ProcessState.Settled) ||
            (tradeState == TradeState.Terminated),
            "Trade state is not 'Initiated' or 'Settled' or 'Terminated'."
        );
        _;
    }

    // #155
    modifier onlyWhenInceptedOrConfirmedOrSettled() {
        require(
            (tradeState == TradeState.Incepted) || (tradeState == TradeState.Confirmed) ||
            (tradeState == TradeState.Active &&
            processState == ProcessState.Settled),
            "Trade state is not 'Initiated' or 'Settled'."
        );
        _;
    }

    modifier onlyWhenFunding() {
        require(
            processState == ProcessState.Funding,
            "Process State is not funding"
        );
        _;
    }

    modifier onlyWhenMarginAccountCheck() {
        require(
            processState == ProcessState.MarginAccountCheck,
            "Process State is not MarginAccountCheck"
        );
        _;
    }

    modifier onlyWhenActive() {
        require(tradeState == TradeState.Active, "Trade State is not Active");
        _;
    }

    modifier onlyWhenMarginAccountLocked() {
        require(
            processState == ProcessState.MarginAccountLocked,
            "Process State is not MarginAccountLocked"
        );
        _;
    }

    modifier onlyWhenValuationAndSettlement() {
        require(
            processState == ProcessState.ValuationAndSettlement,
            "Process State is not ValuationAndSettlement"
        );
        _;
    }


    // #166
    modifier notIsSettlementOrMarginCheck() {
        require(
            !(processState == ProcessState.ValuationAndSettlement ||
        processState == ProcessState.MarginAccountCheck),
            "Process State is Settlement or Margin Account Check"
        );
        _;
    }

*/