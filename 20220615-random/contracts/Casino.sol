//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

contract Casino {
    struct Bet {
        address addressA;
        address addressB;
        uint256 hashB;
        uint256 submissionA;
        uint256 submissionB;
        uint256 value;
        uint256 acceptedAt;
    } // struct Bet

    // Bets, keyed by the commitment value
    mapping(uint256 => Bet) public bets;

    event BetProposed(uint256 indexed hashA, address addressA, uint256 value);

    event BetAccepted(
        uint256 indexed hashA,
        address indexed addressB,
        uint256 hashB
    );

    event SubmissionMade(address submitter, uint256 submission);

    event BetSettled(
        uint256 indexed hashA,
        address winner,
        address loser,
        uint256 value
    );

    // Called by sideA to start the process
    function proposeBet(uint256 hashA) external payable {
        require(
            bets[hashA].value == 0,
            "There is already a bet on that commitment."
        );
        require(msg.value > 0, "You need to actually bet something.");

        bets[hashA].addressA = msg.sender;
        bets[hashA].value = msg.value;

        emit BetProposed(hashA, msg.sender, msg.value);
    } // function proposeBet

    // Called by sideB to continue
    function acceptBet(uint256 hashA, uint256 hashB) external payable {
        require(bets[hashA].acceptedAt == 0, "Bet has already been accepted.");
        require(bets[hashA].addressA != address(0), "Nobody made that bet.");
        require(
            msg.value == bets[hashA].value,
            "Need to bet the same amount as your counterparty."
        );

        bets[hashA].addressB = msg.sender;
        bets[hashA].hashB = hashB;
        bets[hashA].acceptedAt = block.timestamp;

        emit BetAccepted(hashA, msg.sender, hashB);
    } // function acceptBet

    // Called by either side to submit their unhashed entry
    // after both sides agree to bet
    // If 30 min have passed since the bet handshake,
    // the bet has expired and the first side to submit gets paid
    function placeBetSubmission(
        uint256 hashA,
        uint256 hashedSubmission,
        uint256 unhashedSubmission
    ) external {
        require(
            bets[hashA].acceptedAt != 0,
            "This bet has not been accepted yet or does not exist"
        );

        require(
            (block.timestamp - bets[hashA].acceptedAt) < 1800 seconds,
            "The bet submission window of 30 min has expired. Either party can now evaluate the bet."
        );

        require(
            (msg.sender == bets[hashA].addressA && hashedSubmission == hashA) ||
                (msg.sender == bets[hashA].addressB &&
                    hashedSubmission == bets[hashA].hashB),
            "You are not party to this bet, are not submitting for the correct side, or the hash does not match your original hash."
        );

        uint256 computedHashed = uint256(
            keccak256(abi.encodePacked(unhashedSubmission))
        );

        require(
            computedHashed == hashedSubmission,
            "Your unhashed submission does not match its hash"
        );

        if (msg.sender == bets[hashA].addressA && hashedSubmission == hashA) {
            require(
                bets[hashA].submissionA == 0,
                "You have already submitted."
            );
            bets[hashA].submissionA = unhashedSubmission;
        } else {
            require(
                bets[hashA].submissionB == 0,
                "You have already submitted."
            );
            bets[hashA].submissionB = unhashedSubmission;
        }

        emit SubmissionMade(msg.sender, unhashedSubmission);
    }

    function evaluateBet(uint256 hashA) external payable {
        require(
            bets[hashA].acceptedAt != 0,
            "This bet has not been accepted yet or does not exist"
        );

        uint256 elapsedTime = block.timestamp - bets[hashA].acceptedAt;
        bool sent = false;

        address payable winner;
        address payable loser;

        if (bets[hashA].submissionA != 0 && bets[hashA].submissionB != 0) {
            uint256 result = bets[hashA].submissionA ^ bets[hashA].submissionB;
            // Pay and emit an event
            if (result % 2 == 0) {
                // sideA wins
                winner = payable(bets[hashA].addressA);
                loser = payable(bets[hashA].addressB);
            } else {
                // sideB wins
                winner = payable(bets[hashA].addressB);
                loser = payable(bets[hashA].addressA);
            }
        } else if (elapsedTime > 1800 seconds) {
            // bet has expired, determine who to pay
            if (bets[hashA].submissionA == 0) {
                winner = payable(bets[hashA].addressB);
                loser = payable(bets[hashA].addressA);
            } else if (bets[hashA].submissionB == 0) {
                winner = payable(bets[hashA].addressA);
                loser = payable(bets[hashA].addressB);
            } else if (msg.sender == bets[hashA].addressA) {
                winner = payable(bets[hashA].addressA);
                loser = payable(bets[hashA].addressB);
            } else if (msg.sender == bets[hashA].addressB) {
                winner = payable(bets[hashA].addressB);
                loser = payable(bets[hashA].addressA);
            }
        }

        if (winner != payable(0)) {
            winner.transfer(2 * bets[hashA].value);
            emit BetSettled(hashA, winner, loser, bets[hashA].value);
            delete bets[hashA];
            sent = true;
        }

        require(
            sent,
            "Not all submissions in or 30 min has not elapsed since bet was accepted."
        );
    } // function evaluateBet
} // contract Casino
