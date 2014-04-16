adUserSync
==========

Performs synchronization (of sorts) with Active Directory. 
 
It's designed to be run via CRON to make sure that a QualysGuard user gets deactivated when that user is deprovisioned in Active Directory. It can also create users and flag cases (but not change them) where a user's QualysGuard role should be changed.
 
Here's what it WILL do:

* Read a list of all users in Active Directory and determine the QG role they should have based on their AD group memberhsip.
* Try to match those up with users in QualysGuard (via external ID, first name + lastname, or email)
* Create accounts for users in AD that aren't in QualysGuard
* Deactivate accounts in QG for users that are disabled or non-existent in AD (with --qgonlyusers as the exceptions)
* Create a listing of actions that require UI work (such as when a manager becomes a reader)
 
Here's what it WON'T do:

* Synchronize passwords
* Provide single-sign-on
* Perform complex matching/permissions logic
* Be robust or support any kind of error conditions (again,  * * it's a proof-of-concept)