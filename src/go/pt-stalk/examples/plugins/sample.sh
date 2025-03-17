#!/bin/bash

# This is a sample plugin for pt-stalk that demonstrates the available hooks

before_stalk() {
    echo "Starting stalker with:"
    echo "  Function: $PT_FUNCTION"
    echo "  Variable: $PT_VARIABLE"
    echo "  Threshold: $PT_THRESHOLD"
}

before_collect() {
    local prefix="$1"
    echo "About to collect metrics with prefix: $prefix"
    echo "Output directory: $PT_DEST/$prefix"
}

after_collect() {
    local prefix="$1"
    echo "Finished collecting metrics with prefix: $prefix"
    
    # Example: Calculate total size of collected data
    du -sh "$PT_DEST/$prefix"
}

after_collect_sleep() {
    echo "Finished sleeping after collection"
}

after_interval_sleep() {
    echo "Finished interval sleep"
}

after_stalk() {
    echo "Stalker finished"
} 