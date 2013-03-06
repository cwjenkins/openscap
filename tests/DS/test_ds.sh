#!/usr/bin/env bash

# Author:
#   Martin Preisler <mpreisle@redhat.com>

set -e -o pipefail

. ${srcdir}/../test_common.sh

# Test Cases.

function assert_correct_xlinks()
{
	local DS=$1
	# First of all make sure that there is at least one ds:component-ref.
	[ "$($XPATH $DS 'count(//*[local-name()="component-ref"])')" != "0" ]
	# We want to catch cases when this element has different namespace.
	local ns=$($XPATH $DS 'name(//*[local-name()="component-ref"][1])' | sed 's/:.*$/:/')
	[ "$ns" != "component-ref" ] || ns=""
	# Ensure there is at least some xlink.
	[ "`$XPATH $DS \"count(//${ns}component-ref/@xlink:href)\"`" != "0" ]
	# This asserts that there is none component-ref/xlink:href broken.
	# Previously, we have seen datastreams with broken xlinks (see trac#286).
	[ "`$XPATH $DS  \"count(//${ns}component-ref[substring(@xlink:href, 2, 10000) != (//${ns}component/@${ns}id | //${ns}extended-component/@${ns}id)])\"`" == "0" ]
}

function test_sds {

    local ret_val=0;

    local DIR="${srcdir}/$1"
    local XCCDF_FILE="$2"
    local SKIP_DIFF="$3"
    local DS_TARGET_DIR="`mktemp -d`"
    local DS_FILE="$DS_TARGET_DIR/sds.xml"

    pushd "$DIR"

    $OSCAP ds sds-compose "$XCCDF_FILE" "$DS_FILE"

    assert_correct_xlinks $DS_FILE
    popd

    pushd "$DS_TARGET_DIR"

    $OSCAP ds sds-split "`basename $DS_FILE`" "$DS_TARGET_DIR"

    rm "$DS_FILE"

    # get rid of filler prefix to make the diff work
    for file in scap_org.open-scap_cref_*;
    do
        mv "$file" "${file#scap_org.open-scap_cref_}"
    done

    popd

    if [ "$SKIP_DIFF" != "1" ]; then
        DIFFERENCE=$(diff --exclude "oscap_debug.log.*" "$DIR" "$DS_TARGET_DIR")

        if [ $? -ne 0 ]; then
            echo "The files are different after going through source data stream! diff follows:"
            echo "$DIFFERENCE"
            echo

            ret_val=1
        fi
    fi

    rm -r "$DS_TARGET_DIR"

    return "$ret_val"
}

function test_eval {

    $OSCAP xccdf eval "${srcdir}/$1"
}

function test_invalid_eval {
    local ret=0
    $OSCAP xccdf eval "${srcdir}/$1" || ret=$?
    return $([ $ret -eq 1 ])
}

function test_invalid_oval_eval {
    local ret=0
    $OSCAP oval eval "${srcdir}/$1" || ret=$?
    return $([ $ret -eq 1 ])
}

function test_eval_id {

    OUT=$($OSCAP xccdf eval --datastream-id $2 --xccdf-id $3 "${srcdir}/$1")
    local RET=$?

    if [ $RET -ne 0 ]; then
        return 1
    fi

    echo "$OUT" | grep $4 > /dev/null
}

function test_eval_complex()
{
	local name=${FUNCNAME}
	local arf=$(mktemp -t ${name}.arf.XXXXXX)
	local stderr=$(mktemp -t ${name}.err.XXXXXX)
	local stdout=$(mktemp -t ${name}.out.XXXXXX)

	$OSCAP xccdf eval \
		--results-arf $arf \
		--datastream-id scap_org.open-scap_datastream_tst2 \
		--xccdf-id scap_org.open-scap_cref_second-xccdf.xml2 \
		--profile xccdf_moc.elpmaxe.www_profile_2 \
		$srcdir/eval_xccdf_id/sds-complex.xml 2> $stderr > $stdout

	# Ensure the sanity of the output.
	[ -f $stderr ]; [ ! -s $stderr ]
	[ "`grep ^Rule $stdout | wc -l`" == "1" ]
	grep ^Rule $stdout | grep xccdf_moc.elpmaxe.www_rule_secon
	rm $stdout

	# Ensure basic correctness of the ARF
	$OSCAP ds rds-validate $arf 2>&1 > $stderr
	[ -f $srderr ]; [ ! -s $stderr ]; rm $stderr
	assert_correct_xlinks $arf

	# Ensure that results are there
	assert_exists() { [ "$($XPATH $arf 'count('"$2"')')" == "$1" ]; }
	assert_exists 1 '//rule-result'
	assert_exists 1 '//rule-result[@idref="xccdf_moc.elpmaxe.www_rule_second"]'
	assert_exists 1 '//rule-result/result'
	assert_exists 1 '//rule-result/result[text()="pass"]'
	rm $arf
}

function test_oval_eval {

    $OSCAP oval eval "${srcdir}/$1"
}

function test_oval_eval_id {

    OUT=$($OSCAP oval eval --datastream-id $2 --oval-id $3 "${srcdir}/$1")
    local RET=$?

    if [ $RET -ne 0 ]; then
        return 1
    fi
    echo "out: $OUT"

    echo "$OUT" | grep $4 > /dev/null
}

function test_rds
{
    local ret_val=0;

    local SDS_FILE="${srcdir}/$1"
    local XCCDF_RESULT_FILE="${srcdir}/$2"
    local OVAL_RESULT_FILE="${srcdir}/$3"
    local DS_TARGET_DIR="`mktemp -d`"
    local DS_FILE="$DS_TARGET_DIR/rds.xml"

    $OSCAP ds rds-create "$SDS_FILE" "$DS_FILE" "$XCCDF_RESULT_FILE" "$OVAL_RESULT_FILE"

    if [ $? -ne 0 ]; then
        ret_val=1
    fi

    assert_correct_xlinks $DS_FILE

    #pushd "$DS_TARGET_DIR"
    #$OSCAP ds sds_split "`basename $DS_FILE`" "$DS_TARGET_DIR"
    #rm sds.xml
    #popd

    rm -r "$DS_TARGET_DIR"

    return "$ret_val"
}

# Testing.
test_init "test_ds.log"

test_run "sds_simple" test_sds sds_simple scap-fedora14-xccdf.xml 0
test_run "sds_multiple_oval" test_sds sds_multiple_oval multiple-oval-xccdf.xml 0
test_run "sds_subdir" test_sds sds_subdir subdir/scap-fedora14-xccdf.xml 1
test_run "sds_extended_component" test_sds sds_extended_component fake-check-xccdf.xml 0
test_run "sds_extended_component_plain_text" test_sds sds_extended_component_plain_text fake-check-xccdf.xml 0

test_run "eval_simple" test_eval eval_simple/sds.xml
test_run "eval_invalid" test_invalid_eval eval_invalid/sds.xml
test_run "eval_invalid_oval" test_invalid_oval_eval eval_invalid/sds-oval.xml
test_run "eval_xccdf_id1" test_eval_id eval_xccdf_id/sds.xml scap_org.open-scap_datastream_tst scap_org.open-scap_cref_first-xccdf.xml first
test_run "eval_xccdf_id2" test_eval_id eval_xccdf_id/sds.xml scap_org.open-scap_datastream_tst scap_org.open-scap_cref_second-xccdf.xml second
test_run "eval_just_oval" test_oval_eval eval_just_oval/sds.xml
test_run "eval_oval_id1" test_oval_eval_id eval_oval_id/sds.xml scap_org.open-scap_datastream_just_oval scap_org.open-scap_cref_scap-oval1.xml "oval:x:def:1"
test_run "eval_oval_id2" test_oval_eval_id eval_oval_id/sds.xml scap_org.open-scap_datastream_just_oval scap_org.open-scap_cref_scap-oval2.xml "oval:x:def:2"
test_run "eval_cpe" test_eval eval_cpe/sds.xml

test_run "rds_simple" test_rds rds_simple/sds.xml rds_simple/results-xccdf.xml rds_simple/results-oval.xml
test_run "rds_testresult" test_rds rds_testresult/sds.xml rds_testresult/results-xccdf.xml rds_testresult/results-oval.xml
test_run "test_eval_complex" test_eval_complex

test_exit

