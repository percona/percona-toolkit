package types

import (
	"math"
	"time"
)

// It should be kept already sorted by timestamp
type LocalTimeline []LogInfo

func (lt LocalTimeline) Add(li LogInfo) LocalTimeline {

	// to deduplicate, it will keep 2 loginfo occurences
	// 1st one for the 1st timestamp found, it will also show the number of repetition
	// 2nd loginfo the keep the last timestamp found, so that we don't loose track
	// so there will be a corner case if the first ever event is repeated, but that is acceptable
	if len(lt) > 1 && li.IsDuplicatedEvent(lt[len(lt)-2], lt[len(lt)-1]) {
		lt[len(lt)-2].RepetitionCount++
		lt[len(lt)-1] = li
	} else {
		lt = append(lt, li)
	}
	return lt
}

// "string" key is a node IP
type Timeline map[string]LocalTimeline

// MergeTimeline is helpful when log files are split by date, it can be useful to be able to merge content
// a "timeline" come from a log file. Log files that came from some node should not never have overlapping dates
func MergeTimeline(t1, t2 LocalTimeline) LocalTimeline {
	if len(t1) == 0 {
		return t2
	}
	if len(t2) == 0 {
		return t1
	}

	startt1 := getfirsttime(t1)
	startt2 := getfirsttime(t2)

	// just flip them, easier than adding too many nested conditions
	// t1: ---O----?--
	// t2: --O-----?--
	if startt1.After(startt2) {
		return MergeTimeline(t2, t1)
	}

	endt1 := getlasttime(t1)
	endt2 := getlasttime(t2)

	// if t2 is an updated version of t1, or t1 an updated of t2, or t1=t2
	// t1: --O-----?--
	// t2: --O-----?--
	if startt1.Equal(startt2) {
		// t2 > t1
		// t1: ---O---O----
		// t2: ---O-----O--
		if endt1.Before(endt2) {
			return t2
		}
		// t1: ---O-----O--
		// t2: ---O-----O--
		// or
		// t1: ---O-----O--
		// t2: ---O---O----
		return t1
	}

	// if t1 superseds t2
	// t1: --O-----O--
	// t2: ---O---O---
	// or
	// t1: --O-----O--
	// t2: ---O----O--
	if endt1.After(endt2) || endt1.Equal(endt2) {
		return t1
	}
	//return append(t1, t2...)

	// t1: --O----O----
	// t2: ----O----O--
	if endt1.After(startt2) {
		// t1: --O----O----
		// t2: ----OO--OO--
		//>t : --O----OOO-- won't try to get things between t1.end and t2.start
		// we assume they're identical, they're supposed to be from the same server
		t2 = CutTimelineAt(t2, endt1)
		// no return here, to avoid repeating the ctx.inherit
	}

	// t1: --O--O------
	// t2: ------O--O--
	t2[len(t2)-1].Ctx.Inherit(t1[len(t1)-1].Ctx)
	return append(t1, t2...)
}

func getfirsttime(l LocalTimeline) time.Time {
	for _, event := range l {
		if event.Date != nil && (event.Ctx.FileType == "error.log" || event.Ctx.FileType == "") {
			return event.Date.Time
		}
	}
	return time.Time{}
}
func getlasttime(l LocalTimeline) time.Time {
	for i := len(l) - 1; i >= 0; i-- {
		if l[i].Date != nil && (l[i].Ctx.FileType == "error.log" || l[i].Ctx.FileType == "") {
			return l[i].Date.Time
		}
	}
	return time.Time{}
}

// CutTimelineAt returns a localtimeline with the 1st event starting
// right after the time sent as parameter
func CutTimelineAt(t LocalTimeline, at time.Time) LocalTimeline {
	var i int
	for i = 0; i < len(t); i++ {
		if t[i].Date.Time.After(at) {
			break
		}
	}

	return t[i:]
}

func (t *Timeline) GetLatestUpdatedContextsByNodes() map[string]LogCtx {
	updatedCtxs := map[string]LogCtx{}
	latestctxs := []LogCtx{}

	for key, localtimeline := range *t {
		if len(localtimeline) == 0 {
			updatedCtxs[key] = NewLogCtx()
			continue
		}
		latestctx := localtimeline[len(localtimeline)-1].Ctx
		latestctxs = append(latestctxs, latestctx)
		updatedCtxs[key] = latestctx
	}

	for _, ctx := range updatedCtxs {
		ctx.MergeMapsWith(latestctxs)
	}
	return updatedCtxs
}

// iterateNode is used to search the source node(s) that contains the next chronological events
// it returns a slice in case 2 nodes have their next event precisely at the same time, which
// happens a lot on some versions
func (t Timeline) IterateNode() []string {
	var (
		nextDate  time.Time
		nextNodes []string
	)
	nextDate = time.Unix(math.MaxInt32, 0)
	for node := range t {
		if len(t[node]) == 0 {
			continue
		}
		curDate := getfirsttime(t[node])
		if curDate.Before(nextDate) {
			nextDate = curDate
			nextNodes = []string{node}
		} else if curDate.Equal(nextDate) {
			nextNodes = append(nextNodes, node)
		}
	}
	return nextNodes
}

func (t Timeline) Dequeue(node string) {

	// dequeue the events
	if len(t[node]) > 0 {
		t[node] = t[node][1:]
	}
}
