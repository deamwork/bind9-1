#!/bin/sh
#
# Copyright (C) 2000, 2001, 2004, 2007, 2009-2016  Internet Systems Consortium, Inc. ("ISC")
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# $Id: tests.sh,v 1.42 2011/12/16 23:01:17 each Exp $

SYSTEMTESTTOP=..
. $SYSTEMTESTTOP/conf.sh

status=0
n=0

# wait for zone transfer to complete
tries=0
while true; do
    if [ $tries -eq 10 ]
    then
        exit 1
    fi

    if grep "example.nil/IN.*Transfer status" ns2/named.run > /dev/null
    then
        break
    else
        echo "I:zones are not fully loaded, waiting..."
        tries=`expr $tries + 1`
        sleep 1
    fi
done

ret=0
echo "I:fetching first copy of zone before update"
$DIG +tcp +noadd +nosea +nostat +noquest +nocomm +nocmd example.nil.\
	@10.53.0.1 axfr -p 5300 > dig.out.ns1 || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

ret=0
echo "I:fetching second copy of zone before update"
$DIG +tcp +noadd +nosea +nostat +noquest +nocomm +nocmd example.nil.\
	@10.53.0.2 axfr -p 5300 > dig.out.ns2 || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

ret=0
echo "I:comparing pre-update copies to known good data"
$PERL ../digcomp.pl knowngood.ns1.before dig.out.ns1 || ret=1
$PERL ../digcomp.pl knowngood.ns1.before dig.out.ns2 || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

ret=0
echo "I:updating zone"
# nsupdate will print a ">" prompt to stdout as it gets each input line.
$NSUPDATE -k ns1/ddns.key <<END > /dev/null || ret=1
server 10.53.0.1 5300
update add updated.example.nil. 600 A 10.10.10.1
add updated.example.nil. 600 TXT Foo
delete t.example.nil.

END
[ $ret = 0 ] || { echo I:failed; status=1; }

echo "I:sleeping 5 seconds for server to incorporate changes"
sleep 5

ret=0
echo "I:fetching first copy of zone after update"
$DIG +tcp +noadd +nosea +nostat +noquest +nocomm +nocmd example.nil.\
	@10.53.0.1 axfr -p 5300 > dig.out.ns1 || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

ret=0
echo "I:fetching second copy of zone after update"
$DIG +tcp +noadd +nosea +nostat +noquest +nocomm +nocmd example.nil.\
	@10.53.0.2 axfr -p 5300 > dig.out.ns2 || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

ret=0
echo "I:comparing post-update copies to known good data"
$PERL ../digcomp.pl knowngood.ns1.after dig.out.ns1 || ret=1
$PERL ../digcomp.pl knowngood.ns1.after dig.out.ns2 || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

ret=0
echo "I:testing local update policy"
pre=`$DIG +short new.other.nil. @10.53.0.1 a -p 5300` || ret=1
[ -z "$pre" ] || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

ret=0
echo "I:updating zone"
# nsupdate will print a ">" prompt to stdout as it gets each input line.
$NSUPDATE -l -p 5300 -k ns1/session.key > /dev/null <<END || ret=1
zone other.nil.
update add new.other.nil. 600 IN A 10.10.10.1
send
END
[ $ret = 0 ] || { echo I:failed; status=1; }

echo "I:sleeping 5 seconds for server to incorporate changes"
sleep 5

ret=0
echo "I:checking result of update"
post=`$DIG +short new.other.nil. @10.53.0.1 a -p 5300` || ret=1
[ "$post" = "10.10.10.1" ] || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

ret=0
echo "I:comparing post-update copy to known good data"
$PERL ../digcomp.pl knowngood.ns1.after dig.out.ns1 || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

ret=0
echo "I:testing zone consistency checks"
# inserting an NS record without a corresponding A or AAAA record should fail
$NSUPDATE -l -p 5300 -k ns1/session.key > nsupdate.out 2>&1 << END && ret=1
update add other.nil. 600 in ns ns3.other.nil.
send
END
grep REFUSED nsupdate.out > /dev/null 2>&1 || ret=1
# ...but should work if an A record is inserted first:
$NSUPDATE -l -p 5300 -k ns1/session.key > nsupdate.out 2>&1 << END || ret=1
update add ns4.other.nil 600 in a 10.53.0.1
send
update add other.nil. 600 in ns ns4.other.nil.
send
END
grep REFUSED nsupdate.out > /dev/null 2>&1 && ret=1
# ...or if an AAAA record does:
$NSUPDATE -l -p 5300 -k ns1/session.key > nsupdate.out 2>&1 << END || ret=1
update add ns5.other.nil 600 in aaaa 2001:db8::1
send
update add other.nil. 600 in ns ns5.other.nil.
send
END
grep REFUSED nsupdate.out > /dev/null 2>&1 && ret=1
# ...or if the NS and A/AAAA are inserted together:
$NSUPDATE -l -p 5300 -k ns1/session.key > nsupdate.out 2>&1 << END || ret=1
update add other.nil. 600 in ns ns6.other.nil.
update add ns6.other.nil 600 in a 10.53.0.1
send
END
grep REFUSED nsupdate.out > /dev/null 2>&1 && ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

echo "I:sleeping 5 seconds for server to incorporate changes"
sleep 5

ret=0
echo "I:checking result of update"
$DIG +short @10.53.0.1 -p 5300 ns other.nil > dig.out.ns1 || ret=1
grep ns3.other.nil dig.out.ns1 > /dev/null 2>&1 && ret=1
grep ns4.other.nil dig.out.ns1 > /dev/null 2>&1 || ret=1
grep ns5.other.nil dig.out.ns1 > /dev/null 2>&1 || ret=1
grep ns6.other.nil dig.out.ns1 > /dev/null 2>&1 || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

ret=0
echo "I:check SIG(0) key is accepted"
key=`$KEYGEN -q -r $RANDFILE -a NSEC3RSASHA1 -b 1024 -T KEY -n ENTITY xxx`
echo "" | $NSUPDATE -k ${key}.private > /dev/null 2>&1 || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

n=`expr $n + 1`
ret=0
echo "I:check TYPE=0 update is rejected by nsupdate ($n)"
$NSUPDATE <<END > nsupdate.out 2>&1 && ret=1
    server 10.53.0.1 5300
    ttl 300
    update add example.nil. in type0 ""
    send
END
grep "unknown class/type" nsupdate.out > /dev/null 2>&1 || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

n=`expr $n + 1`
ret=0
echo "I:check TYPE=0 prerequisite is handled ($n)"
$NSUPDATE -k ns1/ddns.key <<END > nsupdate.out 2>&1 || ret=1
    server 10.53.0.1 5300
    prereq nxrrset example.nil. type0
    send
END
$DIG +tcp version.bind txt ch @10.53.0.1 -p 5300 > dig.out.ns1.$n
grep "status: NOERROR" dig.out.ns1.$n > /dev/null || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

n=`expr $n + 1`
ret=0
echo "I:check that TYPE=0 update is handled ($n)"
echo "a0e4280000010000000100000000060001c00c000000fe000000000000" |
$PERL ../packet.pl -a 10.53.0.1 -p 5300 -t tcp > /dev/null
$DIG +tcp version.bind txt ch @10.53.0.1 -p 5300 > dig.out.ns1.$n
grep "status: NOERROR" dig.out.ns1.$n > /dev/null || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

n=`expr $n + 1`
echo "I:check that TYPE=0 additional data is handled ($n)"
echo "a0e4280000010000000000010000060001c00c000000fe000000000000" |
$PERL ../packet.pl -a 10.53.0.1 -p 5300 -t tcp > /dev/null
$DIG +tcp version.bind txt ch @10.53.0.1 -p 5300 > dig.out.ns1.$n
grep "status: NOERROR" dig.out.ns1.$n > /dev/null || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

n=`expr $n + 1`
echo "I:check that update to undefined class is handled ($n)"
echo "a0e4280000010001000000000000060101c00c000000fe000000000000" |
$PERL ../packet.pl -a 10.53.0.1 -p 5300 -t tcp > /dev/null
$DIG +tcp version.bind txt ch @10.53.0.1 -p 5300 > dig.out.ns1.$n
grep "status: NOERROR" dig.out.ns1.$n > /dev/null || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

n=`expr $n + 1`
echo "I:check that address family mismatch is handled ($n)"
$NSUPDATE <<END > /dev/null 2>&1 && ret=1
server ::1
local 127.0.0.1
update add 600 txt.example.nil in txt "test"
send
END
[ $ret = 0 ] || { echo I:failed; status=1; }


n=`expr $n + 1`
echo "I:check that unixtime serial number is correctly generated ($n)"
oldserial=`$DIG +short unixtime.nil. soa @10.53.0.1 -p 5300 | awk '{print $3}'` || ret=1
$NSUPDATE <<END > /dev/null 2>&1 || ret=1
    server 10.53.0.1 5300
    ttl 600
    update add new.unixtime.nil in a 1.2.3.4
    send
END
now=`$PERL -e 'print time()."\n";'`
sleep 1
serial=`$DIG +short unixtime.nil. soa @10.53.0.1 -p 5300 | awk '{print $3}'` || ret=1
[ "$oldserial" -ne "$serial" ] || ret=1
# allow up to 2 seconds difference between the serial
# number and the unix epoch date but no more
$PERL -e 'exit 1 if abs($ARGV[1] - $ARGV[0]) > 2;' $now $serial || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

if $PERL -e 'use Net::DNS;' 2>/dev/null
then
    echo "I:running update.pl test"
    $PERL update_test.pl -s 10.53.0.1 -p 5300 update.nil. || status=1
else
    echo "I:The second part of this test requires the Net::DNS library." >&2
fi

ret=0
echo "I:fetching first copy of test zone"
$DIG +tcp +noadd +nosea +nostat +noquest +nocomm +nocmd example.nil.\
	@10.53.0.1 axfr -p 5300 > dig.out.ns1 || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

echo "I:fetching second copy of test zone"
$DIG +tcp +noadd +nosea +nostat +noquest +nocomm +nocmd example.nil.\
	@10.53.0.2 axfr -p 5300 > dig.out.ns2 || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

ret=0
echo "I:comparing zones"
$PERL ../digcomp.pl dig.out.ns1 dig.out.ns2 || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

echo "I:SIGKILL and restart server ns1"
cd ns1
$KILL -KILL `cat named.pid`
rm named.pid
cd ..
sleep 10
if 
	$PERL $SYSTEMTESTTOP/start.pl --noclean --restart . ns1
then
	echo "I:restarted server ns1"	
else
	echo "I:could not restart server ns1"
	exit 1
fi
sleep 10

ret=0
echo "I:fetching ns1 after hard restart"
$DIG +tcp +noadd +nosea +nostat +noquest +nocomm +nocmd example.nil.\
	@10.53.0.1 axfr -p 5300 > dig.out.ns1.after || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

ret=0
echo "I:comparing zones"
$PERL ../digcomp.pl dig.out.ns1 dig.out.ns1.after || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

echo "I:begin RT #482 regression test"

ret=0
echo "I:update master"
$NSUPDATE -k ns1/ddns.key <<END > /dev/null || ret=1
server 10.53.0.1 5300
update add updated2.example.nil. 600 A 10.10.10.2
update add updated2.example.nil. 600 TXT Bar
update delete c.example.nil.
send
END
[ $ret = 0 ] || { echo I:failed; status=1; }

sleep 5

if [ ! "$CYGWIN" ]; then
    echo "I:SIGHUP slave"
    $KILL -HUP `cat ns2/named.pid`
else
    echo "I:reload slave"
    $RNDC -c ../common/rndc.conf -s 10.53.0.2 -p 9953 reload > /dev/null 2>&1
fi

sleep 5

ret=0
echo "I:update master again"
$NSUPDATE -k ns1/ddns.key <<END > /dev/null || ret=1
server 10.53.0.1 5300
update add updated3.example.nil. 600 A 10.10.10.3
update add updated3.example.nil. 600 TXT Zap
del d.example.nil.
send
END
[ $ret = 0 ] || { echo I:failed; status=1; }

sleep 5

if [ ! "$CYGWIN" ]; then
    echo "I:SIGHUP slave again"
    $KILL -HUP `cat ns2/named.pid`
else
    echo "I:reload slave again"
    $RNDC -c ../common/rndc.conf -s 10.53.0.2 -p 9953 reload > /dev/null 2>&1
fi

sleep 5

echo "I:check to 'out of sync' message"
if grep "out of sync" ns2/named.run
then
	echo "I: failed (found 'out of sync')"
	status=1
fi

echo "I:end RT #482 regression test"

n=`expr $n + 1`
ret=0
echo "I:start NSEC3PARAM changes via UPDATE on a unsigned zone test ($n)"
$NSUPDATE << EOF
server 10.53.0.3 5300
update add example 3600 nsec3param 1 0 0 -
send
EOF

sleep 1

# the zone is not signed.  The nsec3param records should be removed.
# this also proves that the server is still running.
$DIG +tcp +noadd +nosea +nostat +noquest +nocmd +norec example.\
	@10.53.0.3 nsec3param -p 5300 > dig.out.ns3.$n || ret=1
grep "ANSWER: 0" dig.out.ns3.$n > /dev/null || ret=1
grep "flags:[^;]* aa[ ;]" dig.out.ns3.$n > /dev/null || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

n=`expr $n + 1`
ret=0
echo "I:change the NSEC3PARAM ttl via update ($n)"
$NSUPDATE << EOF
server 10.53.0.3 5300
update add nsec3param.test 3600 NSEC3PARAM 1 0 1 -
send
EOF

sleep 1

$DIG +tcp +noadd +nosea +nostat +noquest +nocmd +norec nsec3param.test.\
        @10.53.0.3 nsec3param -p 5300 > dig.out.ns3.$n || ret=1
grep "ANSWER: 1" dig.out.ns3.$n > /dev/null || ret=1
grep "3600.*NSEC3PARAM" dig.out.ns3.$n > /dev/null || ret=1
grep "flags:[^;]* aa[ ;]" dig.out.ns3.$n > /dev/null || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

n=`expr $n + 1`
ret=0
echo "I:add a new the NSEC3PARAM via update ($n)"
$NSUPDATE << EOF
server 10.53.0.3 5300
update add nsec3param.test 3600 NSEC3PARAM 1 0 4 -
send
EOF

sleep 1

$DIG +tcp +noadd +nosea +nostat +noquest +nocmd +norec nsec3param.test.\
        @10.53.0.3 nsec3param -p 5300 > dig.out.ns3.$n || ret=1
grep "ANSWER: 2" dig.out.ns3.$n > /dev/null || ret=1
grep "NSEC3PARAM 1 0 4 -" dig.out.ns3.$n > /dev/null || ret=1
grep "flags:[^;]* aa[ ;]" dig.out.ns3.$n > /dev/null || ret=1
if [ $ret != 0 ] ; then echo "I: failed"; status=`expr $ret + $status`; fi

n=`expr $n + 1`
ret=0
echo "I:add, delete and change the ttl of the NSEC3PARAM rrset via update ($n)"
$NSUPDATE << EOF
server 10.53.0.3 5300
update delete nsec3param.test NSEC3PARAM
update add nsec3param.test 7200 NSEC3PARAM 1 0 5 -
send
EOF

sleep 1

$DIG +tcp +noadd +nosea +nostat +noquest +nocmd +norec nsec3param.test.\
        @10.53.0.3 nsec3param -p 5300 > dig.out.ns3.$n || ret=1
grep "ANSWER: 1" dig.out.ns3.$n > /dev/null || ret=1
grep "7200.*NSEC3PARAM 1 0 5 -" dig.out.ns3.$n > /dev/null || ret=1
grep "flags:[^;]* aa[ ;]" dig.out.ns3.$n > /dev/null || ret=1
$JOURNALPRINT ns3/nsec3param.test.db.signed.jnl > jp.out.ns3.$n
# intermediate TTL changes.
grep "add nsec3param.test.	7200	IN	NSEC3PARAM 1 0 4 -" jp.out.ns3.$n > /dev/null || ret=1
grep "add nsec3param.test.	7200	IN	NSEC3PARAM 1 0 1 -" jp.out.ns3.$n > /dev/null || ret=1
# delayed adds and deletes.
grep "add nsec3param.test.	0	IN	TYPE65534 .# 6 000180000500" jp.out.ns3.$n > /dev/null || ret=1
grep "add nsec3param.test.	0	IN	TYPE65534 .# 6 000140000100" jp.out.ns3.$n > /dev/null || ret=1
grep "add nsec3param.test.	0	IN	TYPE65534 .# 6 000140000400" jp.out.ns3.$n > /dev/null || ret=1
if [ $ret != 0 ] ; then echo "I: failed"; status=`expr $ret + $status`; fi



echo "I:testing that rndc stop updates the master file"
$NSUPDATE -k ns1/ddns.key <<END > /dev/null || ret=1
server 10.53.0.1 5300
update add updated4.example.nil. 600 A 10.10.10.3
send
END
$PERL $SYSTEMTESTTOP/stop.pl --use-rndc . ns1
# Removing the journal file and restarting the server means
# that the data served by the new server process are exactly
# those dumped to the master file by "rndc stop".
rm -f ns1/*jnl
$PERL $SYSTEMTESTTOP/start.pl --noclean --restart . ns1
$DIG +tcp +noadd +nosea +nostat +noquest +nocomm +nocmd updated4.example.nil.\
	@10.53.0.1 a -p 5300 > dig.out.ns1 || status=1
$PERL ../digcomp.pl knowngood.ns1.afterstop dig.out.ns1 || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

ret=0
echo "I:check that 'nsupdate -l' with a missing keyfile reports the missing file"
$NSUPDATE -l -p 5300 -k ns1/nonexistant.key 2> nsupdate.out < /dev/null
grep ns1/nonexistant.key nsupdate.out > /dev/null || ret=1
if test $ret -ne 0
then
echo "I:failed"; status=1
fi

n=`expr $n + 1`
ret=0
echo "I:check that changes to the DNSKEY RRset TTL do not have side effects ($n)"
$DIG +tcp +noadd +nosea +nostat +noquest +nocomm +nocmd dnskey.test. \
        @10.53.0.3 -p 5300 dnskey | \
	sed -n 's/\(.*\)10.IN/update add \1600 IN/p' |
	(echo server 10.53.0.3 5300; cat - ; echo send ) |
$NSUPDATE 

$DIG +tcp +noadd +nosea +nostat +noquest +nocomm +nocmd dnskey.test. \
	@10.53.0.3 -p 5300 any > dig.out.ns3.$n

grep "600.*DNSKEY" dig.out.ns3.$n > /dev/null || ret=1
grep TYPE65534 dig.out.ns3.$n > /dev/null && ret=1
if test $ret -ne 0
then
echo "I:failed"; status=1
fi

n=`expr $n + 1`
ret=0
echo "I:check notify with TSIG worked ($n)"
# if the alternate view received a notify--meaning, the notify was
# validly signed by "altkey"--then the zonefile update.alt.bk will
# will have been created.
[ -f ns2/update.alt.bk ] || ret=1
if [ $ret -ne 0 ]; then
    echo "I:failed"
    status=1
fi

n=`expr $n + 1`
ret=0
echo "I:check type list options ($n)"
$NSUPDATE -T > typelist.out.T.${n} || { ret=1; echo "I: nsupdate -T failed"; }
$NSUPDATE -P > typelist.out.P.${n} || { ret=1; echo "I: nsupdate -P failed"; }
$NSUPDATE -TP > typelist.out.TP.${n} || { ret=1; echo "I: nsupdate -TP failed"; }
grep ANY typelist.out.T.${n} > /dev/null && { ret=1; echo "I: failed: ANY found (-T)"; }
grep ANY typelist.out.P.${n} > /dev/null && { ret=1; echo "I: failed: ANY found (-P)"; }
grep ANY typelist.out.TP.${n} > /dev/null && { ret=1; echo "I: failed: ANY found (-TP)"; }
grep KEYDATA typelist.out.T.${n} > /dev/null && { ret=1; echo "I: failed: KEYDATA found (-T)"; }
grep KEYDATA typelist.out.P.${n} > /dev/null && { ret=1; echo "I: failed: KEYDATA found (-P)"; }
grep KEYDATA typelist.out.TP.${n} > /dev/null && { ret=1; echo "I: failed: KEYDATA found (-TP)"; }
grep AAAA typelist.out.T.${n} > /dev/null || { ret=1; echo "I: failed: AAAA not found (-T)"; }
grep AAAA typelist.out.P.${n} > /dev/null && { ret=1; echo "I: failed: AAAA found (-P)"; }
grep AAAA typelist.out.TP.${n} > /dev/null || { ret=1; echo "I: failed: AAAA not found (-TP)"; }
if [ $ret -ne 0 ]; then
    echo "I:failed"
    status=1
fi

n=`expr $n + 1`
ret=0
echo "I:check command list ($n)"
(
while read cmd 
do
    echo "$cmd" | $NSUPDATE  > /dev/null 2>&1
    if test $? -gt 1 ; then
	echo "I: failed ($cmd)"
	ret=1
    fi
    echo "$cmd " | $NSUPDATE  > /dev/null 2>&1
    if test $? -gt 1 ; then
	echo "I: failed ($cmd)"
	ret=1
    fi
done
exit $ret
) < commandlist || ret=1
if [ $ret -ne 0 ]; then
    status=1
fi

n=`expr $n + 1`
ret=0
echo "I:check TSIG key algorithms ($n)"
for alg in md5 sha1 sha224 sha256 sha384 sha512; do
    $NSUPDATE -k ns1/${alg}.key <<END > /dev/null || ret=1
server 10.53.0.1 5300
update add ${alg}.keytests.nil. 600 A 10.10.10.3
send
END
done
sleep 2
for alg in md5 sha1 sha224 sha256 sha384 sha512; do
    $DIG +short @10.53.0.1 -p 5300 ${alg}.keytests.nil | grep 10.10.10.3 > /dev/null 2>&1 || ret=1
done
if [ $ret -ne 0 ]; then
    echo "I:failed"
    status=1
fi

n=`expr $n + 1`
ret=0
echo "I:check that ttl is capped by max-ttl ($n)"
$NSUPDATE <<END > /dev/null || ret=1
server 10.53.0.1 5300
update add cap.max-ttl.nil. 600 A 10.10.10.3
update add nocap.max-ttl.nil. 150 A 10.10.10.3
send
END
sleep 2
$DIG @10.53.0.1 -p 5300  cap.max-ttl.nil | grep "^cap.max-ttl.nil.	300" > /dev/null 2>&1 || ret=1
$DIG @10.53.0.1 -p 5300  nocap.max-ttl.nil | grep "^nocap.max-ttl.nil.	150" > /dev/null 2>&1 || ret=1
if [ $ret -ne 0 ]; then
    echo "I:failed"
    status=1
fi

n=`expr $n + 1`
ret=0
echo "I:add a record which is truncated when logged. ($n)"
$NSUPDATE verylarge || ret=1
$DIG +tcp @10.53.0.1 -p 5300 txt txt.update.nil > dig.out.ns1.test$n
grep "ANSWER: 1," dig.out.ns1.test$n > /dev/null || ret=1
grep "adding an RR at 'txt.update.nil' TXT .* \[TRUNCATED\]"  ns1/named.run > /dev/null || ret=1
if [ $ret -ne 0 ]; then
    echo "I:failed"
    status=1
fi

n=`expr $n + 1`
echo "I:check that yyyymmddvv serial number is correctly generated ($n)"
oldserial=`$DIG +short yyyymmddvv.nil. soa @10.53.0.1 -p 5300 | awk '{print $3}'` || ret=1
$NSUPDATE <<END > /dev/null 2>&1 || ret=1
    server 10.53.0.1 5300
    ttl 600
    update add new.yyyymmddvv.nil in a 1.2.3.4
    send
END
now=`$PERL -e '@lt=localtime(); printf "%.4d%0.2d%0.2d00\n",$lt[5]+1900,$lt[4]+1,$lt[3];'`
sleep 1
serial=`$DIG +short yyyymmddvv.nil. soa @10.53.0.1 -p 5300 | awk '{print $3}'` || ret=1
[ "$oldserial" -ne "$serial" ] || ret=1
[ "$serial" -eq "$now" ] || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

#
#  Refactor to use perl to launch the parallel updates.
#
if false
then
n=`expr $n + 1`
echo "I:send many simultaneous updates via a update forwarder ($n)"
ret=0
for i in 0 1 2 3 4 5 6 7
do
(
    for j in 0 1 2 3 4 5 6 7
    do
    (
	$NSUPDATE << EOF
server 10.53.0.3 5300
zone many.test
update add $i-$j.many.test 0 IN A 1.2.3.4
send
EOF
    ) &
    done
    wait
) &
done
wait
dig axfr many.test @10.53.0.1 -p 5300 > dig.out.test$n
lines=`awk '$4 == "A" { l++ } END { print l }' dig.out.test$n`
test ${lines:-0} -eq 64 || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }
fi

n=`expr $n + 1`
echo "I:check check-names processing ($n)"
ret=0
$NSUPDATE << EOF > nsupdate.out1-$n 2>&1
update add # 0 in a 1.2.3.4
EOF
grep "bad owner" nsupdate.out1-$n > /dev/null || ret=1

$NSUPDATE << EOF > nsupdate.out2-$n 2>&1
check-names off
update add # 0 in a 1.2.3.4
EOF
grep "bad owner" nsupdate.out2-$n > /dev/null && ret=1

$NSUPDATE << EOF > nsupdate.out3-$n 2>&1
update add . 0 in mx 0 #
EOF
grep "bad name" nsupdate.out3-$n > /dev/null || ret=1

$NSUPDATE << EOF > nsupdate.out4-$n 2>&1
check-names off
update add . 0 in mx 0 #
EOF
grep "bad name" nsupdate.out4-$n > /dev/null && ret=1

[ $ret = 0 ] || { echo I:failed; status=1; }

n=`expr $n + 1`
echo "I:check adding of delegating NS records processing ($n)"
ret=0
$NSUPDATE -v << EOF > nsupdate.out-$n 2>&1 || ret=1
server 10.53.0.3 5300
zone delegation.test.
update add child.delegation.test. 3600 NS foo.example.net.
update add child.delegation.test. 3600 NS bar.example.net.
send
EOF
$DIG +tcp @10.53.0.3 -p 5300 ns child.delegation.test > dig.out.ns1.test$n
grep "status: NOERROR" dig.out.ns1.test$n > /dev/null 2>&1 || ret=1
grep "AUTHORITY: 2" dig.out.ns1.test$n > /dev/null 2>&1 || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

n=`expr $n + 1`
echo "I:check deleting of delegating NS records processing ($n)"
ret=0
$NSUPDATE -v << EOF > nsupdate.out-$n 2>&1 || ret=1
server 10.53.0.3 5300
zone delegation.test.
update del child.delegation.test. 3600 NS foo.example.net.
update del child.delegation.test. 3600 NS bar.example.net.
send
EOF
$DIG +tcp @10.53.0.3 -p 5300 ns child.delegation.test > dig.out.ns1.test$n
grep "status: NXDOMAIN" dig.out.ns1.test$n > /dev/null 2>&1 || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

n=`expr $n + 1`
echo "I:check that adding too many records is blocked ($n)"
ret=0
$NSUPDATE -v << EOF > nsupdate.out-$n 2>&1 && ret=1
server 10.53.0.3 5300
zone too-big.test.
update add r1.too-big.test 3600 IN TXT r1.too-big.test
send
EOF
grep "update failed: SERVFAIL" nsupdate.out-$n > /dev/null || ret=1
$DIG +tcp @10.53.0.3 -p 5300 r1.too-big.test TXT > dig.out.ns3.test$n
grep "status: NXDOMAIN" dig.out.ns3.test$n > /dev/null || ret=1
grep "records in zone (4) exceeds max-records (3)" ns3/named.run > /dev/null || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

#
#  Add client library tests here
#
n=`expr $n + 1`
echo "I:check that dns_client_update handles prerequisite NXDOMAIN failure ($n)"
$SAMPLEUPDATE -P 5300 -a 10.53.0.1 -a 10.53.0.2 -p "nxdomain exists.sample" \
	add "nxdomain-exists.sample 0 in a 1.2.3.4" > update.out.test$n 2>&1
$SAMPLEUPDATE -P 5300 -a 10.53.0.2 -p "nxdomain exists.sample" \
	add "check-nxdomain-exists.sample 0 in a 1.2.3.4" > update.out.check$n 2>&1
$DIG +tcp @10.53.0.1 -p 5300 a nxdomain-exists.sample > dig.out.ns1.test$n
$DIG +tcp @10.53.0.2 -p 5300 a nxdomain-exists.sample > dig.out.ns2.test$n
$DIG +tcp @10.53.0.2 -p 5300 a check-nxdomain-exists.sample > check.out.ns2.test$n
grep "update failed: YXDOMAIN" update.out.test$n > /dev/null || ret=1
grep "update succeeded" update.out.check$n > /dev/null || ret=1
grep "status: NXDOMAIN" dig.out.ns1.test$n > /dev/null || ret=1
grep "status: NXDOMAIN" dig.out.ns2.test$n > /dev/null || ret=1
grep "status: NOERROR" check.out.ns2.test$n > /dev/null || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

n=`expr $n + 1`
echo "I:check that dns_client_update handles prerequisite YXDOMAIN failure ($n)"
$SAMPLEUPDATE -P 5300 -a 10.53.0.1 -a 10.53.0.2 -p "yxdomain nxdomain.sample" \
	add "yxdomain-nxdomain.sample 0 in a 1.2.3.4" > update.out.test$n 2>&1
$SAMPLEUPDATE -P 5300 -a 10.53.0.2 -p "yxdomain nxdomain.sample" \
	add "check-yxdomain-nxdomain.sample 0 in a 1.2.3.4" > update.out.check$n 2>&1
$DIG +tcp @10.53.0.1 -p 5300 a nxdomain-exists.sample > dig.out.ns1.test$n
$DIG +tcp @10.53.0.2 -p 5300 a nxdomain-exists.sample > dig.out.ns2.test$n
$DIG +tcp @10.53.0.2 -p 5300 a check-nxdomain-exists.sample > check.out.ns2.test$n
grep "update failed: NXDOMAIN" update.out.test$n > /dev/null || ret=1
grep "update succeeded" update.out.check$n > /dev/null || ret=1
grep "status: NXDOMAIN" dig.out.ns1.test$n > /dev/null || ret=1
grep "status: NXDOMAIN" dig.out.ns2.test$n > /dev/null || ret=1
grep "status: NOERROR" check.out.ns2.test$n > /dev/null || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

n=`expr $n + 1`
echo "I:check that dns_client_update handles prerequisite NXRRSET failure ($n)"
$SAMPLEUPDATE -P 5300 -a 10.53.0.1 -a 10.53.0.2 -p "nxrrset exists.sample TXT This RRset exists." \
	add "nxrrset-exists.sample 0 in a 1.2.3.4" > update.out.test$n 2>&1
$SAMPLEUPDATE -P 5300 -a 10.53.0.2 -p "nxrrset exists.sample TXT This RRset exists." \
	add "check-nxrrset-exists.sample 0 in a 1.2.3.4" > update.out.check$n 2>&1
$DIG +tcp @10.53.0.1 -p 5300 a nxrrset-exists.sample > dig.out.ns1.test$n
$DIG +tcp @10.53.0.2 -p 5300 a nxrrset-exists.sample > dig.out.ns2.test$n
$DIG +tcp @10.53.0.2 -p 5300 a check-nxrrset-exists.sample > check.out.ns2.test$n
grep "update failed: YXRRSET" update.out.test$n > /dev/null || ret=1
grep "update succeeded" update.out.check$n > /dev/null || ret=1
grep "status: NXDOMAIN" dig.out.ns1.test$n > /dev/null || ret=1
grep "status: NXDOMAIN" dig.out.ns2.test$n > /dev/null || ret=1
grep "status: NOERROR" check.out.ns2.test$n > /dev/null || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

n=`expr $n + 1`
echo "I:check that dns_client_update handles prerequisite YXRRSET failure ($n)"
$SAMPLEUPDATE -P 5300 -a 10.53.0.1 -a 10.53.0.2 -p "yxrrset no-txt.sample TXT" \
	add "yxrrset-nxrrset.sample 0 in a 1.2.3.4" > update.out.test$n 2>&1
$SAMPLEUPDATE -P 5300 -a 10.53.0.2 -p "yxrrset no-txt.sample TXT" \
	add "check-yxrrset-nxrrset.sample 0 in a 1.2.3.4" > update.out.check$n 2>&1
$DIG +tcp @10.53.0.1 -p 5300 a yxrrset-nxrrset.sample > dig.out.ns1.test$n
$DIG +tcp @10.53.0.2 -p 5300 a yxrrset-nxrrset.sample > dig.out.ns2.test$n
$DIG +tcp @10.53.0.2 -p 5300 a check-yxrrset-nxrrset.sample > check.out.ns2.test$n
grep "update failed: NXRRSET" update.out.test$n > /dev/null || ret=1
grep "update succeeded" update.out.check$n > /dev/null || ret=1
grep "status: NXDOMAIN" dig.out.ns1.test$n > /dev/null || ret=1
grep "status: NXDOMAIN" dig.out.ns2.test$n > /dev/null || ret=1
grep "status: NOERROR" check.out.ns2.test$n > /dev/null || ret=1
[ $ret = 0 ] || { echo I:failed; status=1; }

#
# End client library tests here
#

echo "I:exit status: $status"
[ $status -eq 0 ] || exit 1
