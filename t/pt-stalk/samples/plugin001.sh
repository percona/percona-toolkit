#!/bin/sh

before_stalk() {
   date >> "$OPT_DEST/before_stalk"
}

before_collect() {
   date >> "$OPT_DEST/before_collect"
}

after_collect() {
   date >> "$OPT_DEST/after_collect"
}

after_collect_sleep() {
   date >> "$OPT_DEST/after_collect_sleep"
}

after_stalk() {
   date >> "$OPT_DEST/after_stalk"
}
