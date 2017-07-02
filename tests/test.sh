#!/bin/bash

set -o pipefail

# globals
FAIL=1
PASS=0
VERBOSE=0
FAILURES=0

# cleanup
function cleanup() {
  rm -rf /tmp/qcrypt_test
  unset QCRYPT_MODE
}

# verbosity
function qout() {
  if test "$VERBOSE" == 1 ; then
    while read -r data ; do
      echo -n "$data"
    done

  else
    while read -r data ; do
      :
    done
  fi
}

# get result of test
function tresult() {
  if [[ $? == "$1" ]] ; then
    echo "PASSED"
  else
    echo "FAILED"
    let FAILURES++
  fi
  echo
}

# setup
cleanup
mkdir /tmp/qcrypt_test
cp ../qcrypt /tmp/qcrypt_test
cd /tmp/qcrypt_test || { echo "cd failure"; exit; }
chmod +x qcrypt
export QCRYPT_MODE="TEST"


# test1
echo fail on encrypt while not in working directory
# encrypt file outside working directory
mkdir dir \
  && touch dir/file \
  && ./qcrypt -e dir/file | qout
tresult $FAIL

# test2
echo warn when re-encrypt but allow
# encrypt file
# encrypt archive
echo "hello" > test2 \
  && ./qcrypt -e test2 | qout \
  && [[ -e test2.zaes256 ]] \
  \
  && ./qcrypt -e test2.zaes256 <<< $'y\n' | qout \
  && [[ -e test2.zaes256.zaes256 ]]
tresult $PASS

# test3
echo encrypt with tar, decrypt with tar
# encrypt with tar
# decrypt with tar
echo "hello" > test3 \
  && sha=$(sha1sum test3) \
  && ./qcrypt -e -t test3 | qout \
  && [[ -e test3.taes256 ]] \
  \
  && ./qcrypt -d -t test3.taes256 | qout \
  && [[ -e test3 ]] \
  && [[ "$sha" = "$(sha1sum test3)" ]]
tresult $PASS

# test4
echo encrypt with tar, decrypt with zip when file extension is provided
# encrypt with tar
# decrypt with zip
echo "hello" > test4 \
  && ./qcrypt -e -t test4 | qout \
  && [[ -e test4.taes256 ]] \
  \
  && ./qcrypt -d -z test4.taes256 | qout \
  && [[ -e test4 ]]
tresult $PASS

# test5
echo encrypt with zip, decrypt with zip
# encrypt with zip
# decrypt with zip
echo "hello" > test5 \
  && sha=$(sha1sum test5) \
  && ./qcrypt -e -z test5 | qout \
  && [[ -e test5.zaes256 ]] \
  \
  && ./qcrypt -d -z test5.zaes256 | qout \
  && [[ -e test5 ]] \
  && [[ "$sha" = "$(sha1sum test5)" ]]
tresult $PASS

# test6
echo warn when decryption output will overwrite existing file
# encrypt file
# create file with original name
# decrypt file, reject overwrite
# ensure new file with same name hasn't changed
echo "hello" > test6 \
  && ./qcrypt -e test6 | qout \
  && [[ -e test6.zaes256 ]] \
  \
  && ! [[ -e test6 ]] \
  && echo testinfo > test6 \
  \
  && ./qcrypt -d test6.zaes256 <<< $'n\n' | qout \
  && test "testinfo" == "$(cat test6)"
tresult $PASS

# test7
echo check for encryption failure
# create fake encrypted file
# decrypt the fake archive
echo "hello" > test7.zaes256 \
  && ./qcrypt -d test7.zaes256 | qout
tresult $FAIL

# test8
echo check auto encryption normal usage
# encrypt file
# decrypt file
echo "hello" > test8 \
  && ./qcrypt -a test8 | qout \
  && [[ -e test8.zaes256 ]] \
  \
  && ./qcrypt -a test8.zaes256 | qout \
  && [[ -e test8 ]]
tresult $PASS

# test9
echo rename archive after encryption using zip
# encrypt file with zip
# rename to non qcrypt extension
# decrypt file with zip
echo "hello" > test9 \
  && ./qcrypt -e test9 | qout \
  && [[ -e test9.zaes256 ]] \
  \
  && mv test9.zaes256 test9.z \
  && ./qcrypt -d -z test9.z <<< $'y\n' | qout \
  && [[ -e test9 ]]
tresult $PASS

# test10
echo rename archive after encryption with tar
# encrypt file with tar
# rename to non qcrypt extension
# decrypt file with tar
echo "hello" > test10 \
  && ./qcrypt -e -t test10 | qout \
  && [[ -e test10.taes256 ]] \
  \
  && mv test10.taes256 test10.t \
  && ./qcrypt -d -t test10.t <<< $'y\n' | qout \
  && [[ -e test10 ]]
tresult $PASS

# test11
echo rename archive after encryption but use the wrong decompression program
# encrypt file with zip
# rename to non qcrypt extension
# decrypt file with tar
echo "hello" > test11 \
  && ./qcrypt -e -t test11 | qout \
  && [[ -e test11.taes256 ]] \
  \
  && mv test11.taes256 test11.t \
  && ./qcrypt -d -z test11.t <<< $'y\n' | qout
tresult $FAIL

# test12
echo warn if file with output name already exists during encryption
# create file
# create file.zaes256
# try to encrypt file, reject overwrite
# ensure original file hasn't changed
echo "hello" > test12 \
  && echo testinfo > test12.zaes256 \
  && ./qcrypt -e test12 <<< $'n\n' | qout \
  && test "testinfo" == "$(cat test12.zaes256)"
tresult $PASS

if (( FAILURES )); then
  echo "Finished with $FAILURES failures."
  echo "Inspect /tmp/qcrypt_test for information"
else
  cleanup
fi
