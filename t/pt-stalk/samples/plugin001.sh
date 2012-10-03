#!/bin/sh

before_stalk_hook() {
   date >> "$OPT_DEST/before_stalk_hook"
}

before_collect_hook() {
   date >> "$OPT_DEST/before_collect_hook"
}

after_collect_hook() {
   date >> "$OPT_DEST/after_collect_hook"
}

after_collect_sleep_hook() {
   date >> "$OPT_DEST/after_collect_sleep_hook"
}

after_stalk_hook() {
   date >> "$OPT_DEST/after_stalk_hook"
}
