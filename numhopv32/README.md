numhopv3
========

Gets traceroute information for specified asset groups and timeframe and calculates useful stats.

Prints:

* Number of hosts
* Average number of hops
* Standard deviation
* Systems FAR from their scanner (those with more hops than 68% of all others ~ AVERAGE + 1*STDEV)
* Systems CLOSE to their scanner (those with less hops than 68% of all others ~ AVERAGE - 1*STDEV)