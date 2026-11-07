// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title RoscaCommittee - an on-chain "BC" / rotating savings committee
/// @notice Fixed members each pay the same amount every round. When everyone
///         has paid, the whole pot goes to that round's recipient. Recipients
///         are chosen in the order members joined, so every member receives
///         the pot exactly once.
contract RoscaCommittee {
    uint256 private immutable contribution; // wei each member pays per round
    uint256 private immutable maxMembers;   // committee size = number of rounds

    address[] private members;
    mapping(address => bool) private isMember;
    mapping(uint256 => mapping(address => bool)) private paid; // round => member => paid?
    uint256 private round;     // current round (0-based)
    uint256 private paidCount; // members who paid this round

    event Joined(address indexed member, uint256 memberCount);
    event Contributed(address indexed member, uint256 round);
    event PotPaid(address indexed recipient, uint256 round, uint256 amount);

    constructor(uint256 _contribution, uint256 _maxMembers) {
        require(_contribution > 0, "Contribution must be > 0");
        require(_maxMembers >= 2, "Need at least 2 members");
        contribution = _contribution;
        maxMembers = _maxMembers;
    }

    /// WRITE 1: take a seat in the committee (payout order = join order).
    function join() external {
        require(!isMember[msg.sender], "Already a member");
        require(members.length < maxMembers, "Committee is full");
        isMember[msg.sender] = true;
        members.push(msg.sender);
        emit Joined(msg.sender, members.length);
    }

    /// WRITE 2: pay this round's contribution. The last payer triggers the payout.
    function contribute() external payable {
        require(members.length == maxMembers, "Committee not full yet");
        require(round < maxMembers, "Committee finished");
        require(isMember[msg.sender], "Not a member");
        require(!paid[round][msg.sender], "Already paid this round");
        require(msg.value == contribution, "Send the exact contribution");

        paid[round][msg.sender] = true;
        paidCount++;
        emit Contributed(msg.sender, round);

        if (paidCount == maxMembers) {
            uint256 finished = round;
            address recipient = members[finished];
            uint256 pot = contribution * maxMembers;
            round++;        // update state before sending ETH
            paidCount = 0;
            (bool ok, ) = payable(recipient).call{value: pot}("");
            require(ok, "Payout failed");
            emit PotPaid(recipient, finished, pot);
        }
    }

    /// READ 1: list of members in payout order.
    function getMembers() external view returns (address[] memory) {
        return members;
    }

    /// READ 2: everything the UI needs about the committee and current round.
    function getRoundInfo() external view returns (
        uint256 contributionWei,
        uint256 size,
        uint256 memberCount,
        uint256 currentRound,
        uint256 paidThisRound,
        address recipient,
        bool completed
    ) {
        completed = round >= maxMembers;
        bool started = members.length == maxMembers;
        recipient = (started && !completed) ? members[round] : address(0);
        return (contribution, maxMembers, members.length, round, paidCount, recipient, completed);
    }

    /// READ 3: has this address paid in the current round?
    function hasPaid(address who) external view returns (bool) {
        return paid[round][who];
    }
}
