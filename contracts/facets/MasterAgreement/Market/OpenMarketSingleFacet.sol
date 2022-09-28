// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.16;

import { AppStorage, RequestForQuote, Position } from "../../../libraries/LibAppStorage.sol";
import { LibHedgers } from "../../../libraries/LibHedgers.sol";
import { LibMaster } from "../../../libraries/LibMaster.sol";
import { C } from "../../../C.sol";
import "../../../libraries/LibEnums.sol";

contract OpenMarketSingleFacet {
    AppStorage internal s;

    function requestOpenMarketSingle(
        address partyB,
        uint256 marketId,
        PositionType positionType,
        Side side,
        uint256 usdAmountToSpend,
        uint256 leverage,
        uint256[2] memory expectedUnits
    ) external returns (RequestForQuote memory rfq) {
        require(msg.sender != partyB, "Parties can not be the same");
        (bool validHedger, ) = LibHedgers.isValidHedger(partyB);
        require(validHedger, "Invalid hedger");

        if (positionType == PositionType.CROSS) {
            uint256 numOpenPositionsCross = s.ma._openPositionsCrossList[msg.sender].length;
            require(numOpenPositionsCross <= C.getMaxOpenPositionsCross(), "Max open positions cross reached");
        }

        rfq = LibMaster.onRequestForQuote(
            msg.sender,
            partyB,
            marketId,
            positionType,
            OrderType.MARKET,
            HedgerMode.SINGLE,
            side,
            usdAmountToSpend,
            leverage,
            expectedUnits[0],
            expectedUnits[1]
        );

        // TODO: emit event
    }

    function cancelOpenMarketSingle(uint256 rfqId) external {
        RequestForQuote storage rfq = s.ma._requestForQuotesMap[rfqId];

        require(rfq.partyA == msg.sender, "Invalid party");
        require(rfq.hedgerMode == HedgerMode.SINGLE, "Invalid hedger mode");
        require(rfq.orderType == OrderType.MARKET, "Invalid order type");
        require(rfq.state == RequestForQuoteState.ORPHAN, "Invalid RFQ state");

        rfq.state = RequestForQuoteState.CANCELATION_REQUESTED;
        rfq.mutableTimestamp = block.timestamp;

        // TODO: emit the event
    }

    function forceCancelOpenMarketSingle(uint256 rfqId) public {
        RequestForQuote storage rfq = s.ma._requestForQuotesMap[rfqId];

        require(rfq.partyA == msg.sender, "Invalid party");
        require(rfq.hedgerMode == HedgerMode.SINGLE, "Invalid hedger mode");
        require(rfq.orderType == OrderType.MARKET, "Invalid order type");
        require(rfq.state == RequestForQuoteState.CANCELATION_REQUESTED, "Invalid RFQ state");
        require(rfq.mutableTimestamp + C.getRequestTimeout() < block.timestamp, "Request Timeout");

        // Update the RFQ state.
        rfq.state = RequestForQuoteState.CANCELED;
        rfq.mutableTimestamp = block.timestamp;

        // Update RFQ mapping.
        LibMaster.removeOpenRequestForQuote(rfq.partyA, rfqId);

        // Return the collateral to partyA.
        uint256 reservedMargin = rfq.lockedMargin + rfq.protocolFee + rfq.liquidationFee + rfq.cva;
        s.ma._lockedMarginReserved[msg.sender] -= reservedMargin;
        s.ma._marginBalances[msg.sender] += reservedMargin;

        // TODO: emit event
    }

    function acceptCancelOpenMarketSingle(uint256 rfqId) external {
        RequestForQuote storage rfq = s.ma._requestForQuotesMap[rfqId];

        require(rfq.partyB == msg.sender, "Invalid party");
        require(rfq.hedgerMode == HedgerMode.SINGLE, "Invalid hedger mode");
        require(rfq.orderType == OrderType.MARKET, "Invalid order type");
        require(rfq.state == RequestForQuoteState.CANCELATION_REQUESTED, "Invalid RFQ state");

        // Update the RFQ state.
        rfq.state = RequestForQuoteState.CANCELED;
        rfq.mutableTimestamp = block.timestamp;

        // Update RFQ mapping.
        LibMaster.removeOpenRequestForQuote(rfq.partyA, rfqId);

        // Return the collateral to partyA.
        uint256 reservedMargin = rfq.lockedMargin + rfq.protocolFee + rfq.liquidationFee + rfq.cva;
        s.ma._lockedMarginReserved[rfq.partyA] -= reservedMargin;
        s.ma._marginBalances[rfq.partyA] += reservedMargin;
    }

    function rejectOpenMarketSingle(uint256 rfqId) external {
        RequestForQuote storage rfq = s.ma._requestForQuotesMap[rfqId];

        require(rfq.partyB == msg.sender, "Invalid party");
        require(rfq.hedgerMode == HedgerMode.SINGLE, "Invalid hedger mode");
        require(rfq.orderType == OrderType.MARKET, "Invalid order type");
        require(
            rfq.state == RequestForQuoteState.ORPHAN || rfq.state == RequestForQuoteState.CANCELATION_REQUESTED,
            "Invalid RFQ state"
        );

        // Update the RFQ
        rfq.state = RequestForQuoteState.REJECTED;
        rfq.mutableTimestamp = block.timestamp;

        // Update RFQ mapping.
        LibMaster.removeOpenRequestForQuote(rfq.partyA, rfqId);

        // Return the collateral to partyA
        uint256 reservedMargin = rfq.lockedMargin + rfq.protocolFee + rfq.liquidationFee + rfq.cva;
        s.ma._lockedMarginReserved[rfq.partyA] -= reservedMargin;
        s.ma._marginBalances[rfq.partyA] += reservedMargin;

        // TODO: emit event
    }

    function fillOpenMarketSingle(
        uint256 rfqId,
        uint256 filledAmountUnits,
        uint256 avgPriceUsd
    ) external returns (Position memory position) {
        RequestForQuote storage rfq = s.ma._requestForQuotesMap[rfqId];

        require(rfq.partyB == msg.sender, "Invalid party");
        require(rfq.hedgerMode == HedgerMode.SINGLE, "Invalid hedger mode");
        require(rfq.orderType == OrderType.MARKET, "Invalid order type");

        position = LibMaster.onFillOpenMarket(msg.sender, rfqId, filledAmountUnits, avgPriceUsd);

        // TODO: emit event
    }
}
