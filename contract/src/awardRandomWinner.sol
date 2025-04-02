// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "../lib/chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import "../lib/chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import "../lib/chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";

contract AutomatedLottery is VRFConsumerBaseV2, AutomationCompatibleInterface {
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator = 
        VRFCoordinatorV2Interface(0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625);
    uint64 private immutable i_subscriptionId = 4529;
    bytes32 private immutable i_gasLane = 0x121a88b1a5ad1d8a8657a43e38c89c7b7cbec83f8fc91dd110f9fe4fc9d2f384;
    uint32 private immutable i_callbackGasLimit = 1000000;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 public entranceFee = 0.01 ether;
    address payable[] private players;
    address private currentWinner;
    uint256 private lastTimeStamp;
    uint256 private immutable interval = 300;

    event LotteryEnter(address indexed player);
    event RequestedLotteryWinner(uint256 indexed requestId);
    event WinnerPicked(address indexed winner, uint256 amount);

    constructor() VRFConsumerBaseV2(address(i_vrfCoordinator)) {
        lastTimeStamp = block.timestamp;
    }

    function playInLottery() public payable {
        if (msg.value < entranceFee) {
            revert("Not enough ETH to enter lottery");
        }

        players.push(payable(msg.sender));
        emit LotteryEnter(msg.sender);
    }

    function checkUpkeep(
        bytes memory /* checkData */
    )
        public
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performData */)
    {
        bool timePassed = ((block.timestamp - lastTimeStamp) > interval);
        bool hasPlayers = (players.length > 1);
        bool hasBalance = address(this).balance > 0;
        upkeepNeeded = (timePassed && hasPlayers && hasBalance);
        return (upkeepNeeded, "");
    }

    function performUpkeep(bytes calldata /* performData */) external override {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert("Upkeep not needed");
        }
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
        emit RequestedLotteryWinner(requestId);
    }

    function fulfillRandomWords(
        uint256 /* requestId */,
        uint256[] memory randomWords
    ) internal override {
        uint256 winnerIndex = randomWords[0] % players.length;
        address payable recentWinner = players[winnerIndex];
        currentWinner = recentWinner;
        players = new address payable[](0);
        lastTimeStamp = block.timestamp;
        uint256 prizeAmount = (address(this).balance * 95) / 100;
        (bool success, ) = recentWinner.call{value: prizeAmount}("");
        if (!success) {
            revert("Transfer failed");
        }
        emit WinnerPicked(recentWinner, prizeAmount);
    }

    function getEntranceFee() public view returns (uint256) {
        return entranceFee;
    }

    function getRecentWinner() public view returns (address) {
        return currentWinner;
    }

    function getLastTimeStamp() public view returns (uint256) {
        return lastTimeStamp;
    }
}
