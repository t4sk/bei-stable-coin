// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// Flapper
/*
Flapper is a Surplus Auction. 
These auctions are used to auction off a fixed amount of the surplus Dai 
in the system for MKR. This surplus Dai will come from the Stability Fees 
that are accumulated from Vaults. In this auction type, bidders compete 
with increasing amounts of MKR. Once the auction has ended, 
the Dai auctioned off is sent to the winning bidder. 
The system then burns the MKR received from the winning bid.
*/
