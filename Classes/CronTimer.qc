# -*- mode: qore; indent-tabs-mode: nil -*-
# CronTimer

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style

class CronTriggerRange {
    private {
        int min;
        int max;

        # temporary hash of set values
        hash<string, bool> value_set;

        # list of all values
        list<int> value_list = ();

        string name;
    }

    constructor(string n_name, softint n_min, softint n_max) {
        name = n_name;
        min = n_min;
        max = n_max;
    }

    # returns True if all possible elements are set
    bool isAll() {
        return elements value_list == (max - min + 1);
    }

    int first() {
        return value_list[0];
    }

    int last() {
        return value_list.last();
    }

    string toString() {
        if (elements value_list == (max - min + 1))
            return "*";
        else if (!value_list)
            return "-";

        string str = "";
        int last = -99;
        bool range;
        foreach int e in (value_list) {
            on_exit last = e;
            if (e === last + 1) {
                range = True;
                continue;
            } else if (range) {
                str += "-" + last;
                range = False;
            }
            if ($#)
                str += ",";
            str += string(e);
        }
        if (range)
            str += "-" + last;

        return str;
    }

    setAll(int rpt = 0) {
        value_list = ();
        for (int i = min; i <= max; ++i) {
            if (rpt && ((i - min) % rpt))
                continue;
            value_set{i} = True;
        }
    }

    setRange(softint n_min, softint n_max, int rpt = 0) {
        if (n_min == n_max)
            return set(n_min);

        if (n_min > n_max) {
            int t = n_min;
            n_min = n_max;
            n_max = t;
        }

        if (n_min < min)
            throw "CRON-TIMER-ERROR", sprintf("%s: lower bound of range (%d) is less than the minimum value (%d)", name, n_min, min);

        if (n_max > max)
            throw "CRON-TIMER-ERROR", sprintf("%s: upper bound of range (%d) is greater than the maximum value (%d)", name, n_max, max);

        for (int i = n_min; i <= n_max; ++i) {
            if (rpt && ((i - n_min) % rpt))
                continue;
            value_set{i} = True;
        }
    }

    set(string v) {
        if (v !~ /[0-9]+/)
            throw "CRON-TIMER-ERROR", sprintf("input value: %y is not numeric and therefore cannot be parsed; %y values must be numeric", v, name);
        set(int(v));
    }

    set(int v) {
        if (v < min)
            throw "CRON-TIMER-ERROR", sprintf("%s: value (%d) is less than the minimum value (%d)", name, v, min);

        if (v > max)
            throw "CRON-TIMER-ERROR", sprintf("%s: value (%d) is greater than the maximum value (%d)", name, v, max);

        value_set{v} = True;
    }

    list<int> getValues() {
        return value_list;
    }

    parse(string input) {
        #printf("CronTriggerRange::parse(%y) %s\n", input, name);
        # remove spaces
        input =~ s/ +//g;
        if (input =~ /,/) {
            list<string> l = split(",", input);
            trim l;
            foreach string e in (l) {
                parseSingle(e);
            }
        } else
            parseSingle(input);

        # finalize hash to ordered list
        finalize();
        #printf("CronTriggerRange::parse(%y) %s values: %y\n", input, name, l);
    }

    private parseSingle(string e) {
        #printf("CronTriggerRange::parseSingle(%y) %s (min: %d max: %d)\n", e, name, min, max);
        # see if there is a skip/repeat specification
        softint rpt;
        if (e =~ /\/[0-9]+$/) {
            rpt = (e =~ x/\/([0-9]+)$/)[0];
            if (!rpt)
                throw "CRON-ERROR", sprintf("%s: cannot parse skip/repeat specification: %y", name, e);
            if (rpt >= (max + 1 - min))
                throw "CRON-ERROR", sprintf("%s: cannot parse skip/repeat specification: %y; repeat value (%y) is greater than or equal to the maximum value of the range (%y) for %s", name, e, rpt, max + 1 - min, name);
            e = (e =~ x/(.*)\/[0-9]+$/)[0];
        }

        # set all for wildcards
        if (e == "*") {
            setAll(rpt);
            return;
        }

        # parse a range
        if (e =~ /-/) {
            list<string> l1 = split("-", e);
            if (elements l1 != 2)
                throw "CRON-ERROR", sprintf("%s: cannot parse range: %y", name, e);

            setRange(l1[0], l1[1], rpt);
            return;
        }

        if (rpt)
            throw "CRON-ERROR", sprintf("%s: cannot accept a skip/repeat specification for a single value: \"%s/%d\"", name, e, rpt);

        # set a single value
        set(e);
    }

    private finalize() {
        if (!value_set) {
            throw "CRON-ERROR", sprintf("%s: illegal empty range set", name);
        }

        # sort keys as integers
        value_list = map $1, sort(map $1.toInt(), keys remove value_set);
    }
}

class DowCronTriggerRange inherits CronTriggerRange {
    public {
        const Days = {
            "sun": 0,
            "mon": 1,
            "tue": 2,
            "wed": 3,
            "thu": 4,
            "fri": 5,
            "sat": 6,
        };
    }

    constructor() : CronTriggerRange("day of the week", 0, 6) {
    }

    private int match(string d) {
        d = tolower(d);
        if (strlen(d) != 3)
            throw "CRON-DAYOFWEEK-ERROR", sprintf("cannot match %y to a day of the week; please use a 3-letter English abbreviation (valid values: %y)", d, Days);

        *int n = Days{d};
        if (!exists n)
            throw "CRON-DAYOFWEEK-ERROR", sprintf("cannot match %y to a day of the week; please use a 3-letter English abbreviation (valid values: %y)", d, Days);
        return n;
    }

    int getDay(string v) {
        if (v =~ /^[0-9]+$/) {
            int val = int(v);
            if (val == 7)
                val = 0;
            return val;
        }
        return match(v);
    }

    set(string v) {
        CronTriggerRange::set(getDay(v));
    }

    setRange(softstring min, softstring max, int rpt = 0) {
        CronTriggerRange::setRange(getDay(min), getDay(max), rpt);
    }
}

class MonthCronTriggerRange inherits CronTriggerRange {
    public {
        const Months = {
            "jan": 1,
            "feb": 2,
            "mar": 3,
            "apr": 4,
            "may": 5,
            "jun": 6,
            "jul": 7,
            "aug": 8,
            "sep": 9,
            "oct": 10,
            "nov": 11,
            "dec": 12,
        };
    }

    constructor() : CronTriggerRange("months", 1, 12) {
    }

    private int match(string d) {
        d = tolower(d);
        if (strlen(d) != 3)
            throw "CRON-MONTH-ERROR", sprintf("cannot match %y to a month; please use a 3-letter English abbreviation (valid values: %y)", d, Months);

        *int n = Months{d};
        if (!exists n)
            throw "CRON-MONTH-ERROR", sprintf("cannot match %y to a month; please use a 3-letter English abbreviation (valid values: %y)", d, Months);
        return n;
    }

    int getMonth(string v) {
        if (v =~ /^[0-9]+$/) {
            int val = int(v);
            return val;
        }
        return match(v);
    }

    set(string v) {
        CronTriggerRange::set(getMonth(v));
    }

    setRange(softstring min, softstring max, int rpt = 0) {
        CronTriggerRange::setRange(getMonth(min), getMonth(max), rpt);
    }
}

class AbstractTrigger {
    # no public members
    public {}

    abstract string toString();

    # finds the next trigger time on or after the specified date
    abstract date findNext(date d);
}

class RecurringTrigger inherits AbstractTrigger {
    private {
        # recurring
        date recurring;
    }

    constructor(date n_recurring) {
        if (!date_info(n_recurring).relative)
            throw "RECURRING-TRIGGER-ERROR", sprintf("date given to constructor: %y is not a relative date/time value", recurring);

        recurring = n_recurring;
    }

    constructor(int n_seconds) {
        if (!n_seconds)
            throw "RECURRING-TRIGGER-ERROR", "recurring in seconds given to constructor cannot be 0";

        recurring = seconds(n_seconds);
    }

    string toString() {
        return sprintf("%y", recurring);
    }

    # finds the next trigger time on or after the specified date
    date findNext(date d) {
        return d + recurring;
    }
}

class CronTrigger inherits AbstractTrigger {
    public {
        CronTriggerRange minutes("minutes", 0, 59);
        CronTriggerRange hours("hours", 0, 23);
        CronTriggerRange days("days", 1, 31);
        DowCronTriggerRange dow();
        MonthCronTriggerRange months();
    }

    constructor(softstring n_minutes, softstring n_hours, softstring n_days, softstring n_months, softstring n_dow) {
        minutes.parse(n_minutes);
        hours.parse(n_hours);
        days.parse(n_days);
        months.parse(n_months);
        dow.parse(n_dow);
    }

    string toString() {
        return sprintf("minutes: %s hours: %s days: %s months: %s dow: %s", minutes.toString(), hours.toString(), days.toString(), months.toString(), dow.toString());
    }

    #! finds the next trigger time on or after the specified date
    date findNext(date d) {
        hash<DateTimeInfo> info = d.info();

        date rv;

        while (True) {
            #printf("CronTrigger::findNext(%y)\nmin: %y\nhour: %y\nday: %y\ndow: %y\nmon: %y\n", d, minutes.getValues(), hours.getValues(), days.getValues(), dow.getValues(), months.getValues());
            #printf("CronTrigger::findNext() info: %y\n", info);

            hash<DateTimeInfo> n = CronTrigger::getNextMonthYear(info.month, info.year, months.getValues());

            #printf("getNextMonthYear() n: %y (m: %y y: %y months.getValues(): %y)\n", n, info.month, info.year, months.getValues());

            # if another month was selected, then take the first value in all other lists
            if (n.month != info.month) {
                n += getFirstDayTrigger(n);
                n += {
                    "hour": hours.first(),
                    "minute": minutes.first(),
                };
            } else {
                # find next trigger after the date
                n += getNextDayMonthYear(n + <DateTimeInfo>{
                    "day": info.day,
                });

                #printf("getNextDayMonthYear() n: %y\n", n);

                if (n.year != info.year
                    || n.month != info.month
                    || n.day != info.day) {
                    n += {
                        "hour": hours.first(),
                        "minute": minutes.first(),
                    };
                } else {
                    # find next trigger after the hour
                    hash<DateTimeInfo> h = getNextHourDayMonthYear(n + info{"hour",});

                    #printf("getNextHourDayMonthYear() n: %y, h: %y\n", n, h);

                    n += h;
                    # got a date; break
                    if (!exists h.minute) {
                        # find the next trigger after the minute
                        n += getNextMinuteHourDayMonthYear(n + info{"minute",});
                    }
                }
            }

            rv = date(sprintf("%04d-%02d-%02dT%02d:%02d:00", n.year, n.month, n.day, n.hour, n.minute));
            # accommodate DST changes
            if (rv < d) {
                ++info.hour;
                continue;
            }
            break;
        }

        return rv;
    }

    # returns the first possible day in the given month
    private hash<DateTimeInfo> getFirstDayTrigger(hash<DateTimeInfo> n) {
        date d = date(sprintf("%04d-%02d-01", n.year, n.month));
        if (days.isAll()) {
            d = getFirstDOW(d);

            # must be in the same year and month
            return d.info(){"day",};
        }

        # if both dow and days have specifications; take the first one
        if (!dow.isAll()) {
            date d1 = getFirstDOW(d);
            date d2 = date(sprintf("%04d-%02d-%02d", n.year, n.month, days.first()));
            #printf("first day both: dow: %y days: %y\n", d1, d2);

            d = d1 < d2 ? d1 : d2;

            # must be in the same year and month
            return d.info(){"day",};
        }

        return <DateTimeInfo>{"day": days.first()};
    }

    # returns a date on or after the passed date that meets the day of week criteria
    private date getFirstDOW(date d) {
        # get first possible day of week
        list<int> l = dow.getValues();
        while (True) {
            if (inlist(get_day_of_week(d), l))
                return d;

            # increment by one day
            d += 1D;
        }
    }

    # returns the first date on or after the passed date that meets the day criteria
    private date getFirstDay(date d) {
        hash<DateTimeInfo> i = d.info();
        list<int> l = days.getValues();

        int bi;
        if (omq_inlist_sorted(i.day, l, \bi))
            return d;

        if (bi)
            return date(sprintf("%04d-%02d-%02d", i.year, i.month, bi));

        d += 1M;
        i = d.info();
        i = CronTrigger::getNextMonthYear(i.month, i.year, months.getValues());
        #printf("getFirstDay(%y) %y\n", d, i);
        return date(sprintf("%04d-%02d-%02d", i.year, i.month, l[0]));
    }

    private hash<DateTimeInfo> getNextMinuteHourDayMonthYear(hash<DateTimeInfo> n) {
        #printf("getNextMinuteHourDayMonthYear() n: %y minutes: %y\n", n, minutes);
        if (n.minute <= minutes.last()) {
            int bm;
            if (omq_inlist_sorted(n.minute, minutes.getValues(), \bm))
                return <DateTimeInfo>{"minute": n.minute};

%ifdef QorusDebugInternals
            QDBG_ASSERT(exists bm);
%endif
            return <DateTimeInfo>{"minute": bm};
        }

        date d = date(sprintf("%04d-%02d-%02dT%02d:00:00", n.year, n.month, n.day, n.hour));
        # get next hour
        ++n.hour;
        # if we are on a different day
        if (n.hour >= 24) {
            return getNextDayMonthYear(d.midnight()) + <DateTimeInfo>{
                "hour": hours.first(),
                "minute": minutes.first(),
            };
        }
        #printf("missed minute, new date: %y\n", d);

        n = d.info(){"year", "month", "day"} + getNextHourDayMonthYear(n);

        return n + <DateTimeInfo>{
            "minute": minutes.first(),
        };
    }

    private hash<DateTimeInfo> getNextHourDayMonthYear(hash<DateTimeInfo> n) {
        if (n.hour <= hours.last()) {
            #printf("getNextHourDayMonthYear() n: %y hours: %y\n", n, hours);

            int bh;
            if (omq_inlist_sorted(n.hour, hours.getValues(), \bh)) {
                return <DateTimeInfo>{"hour": n.hour};
            }

%ifdef QorusDebugInternals
            QDBG_ASSERT(exists bh);
%endif
            return <DateTimeInfo>{"hour": bh, "minute": minutes.first()};
        }

        # get next day
        date d = date(sprintf("%04d-%02d-%02d", n.year, n.month, n.day)) + 1D;

        #printf("missed hour, new date: %y\n", d);

        n = getNextDayMonthYear(d.midnight());
        #printf("getNextHourDayMonthYear() getNextDayMonthYear() returned %y\n", n);

        return n + <DateTimeInfo>{
            "hour": hours.first(),
            "minute": minutes.first(),
        };
    }

    private hash<DateTimeInfo> getNextDayMonthYear(hash<DateTimeInfo> n) {
        date d = date(sprintf("%04d-%02d-%02d", n.year, n.month, n.day));
        return getNextDayMonthYear(d);
    }

    private hash<DateTimeInfo> getNextDayMonthYear(date d) {
        #printf("getNextDayMonthYear(%y) d: %y\n", n, d);

        # get first day in the list greater than or equal to the current day
        if (days.isAll())
            d = getFirstDOW(d);
        else if (!dow.isAll()) {
            # if both dow and days have specifications; take the first one
            date d1 = getFirstDOW(d);
            date d2 = getFirstDay(d);

            #printf("getNextDayMonthYear() both: dow: %y days: %y\n", d1, d2);

            d = d1 < d2 ? d1 : d2;
        } else
            d = getFirstDay(d);

        return d.info(){"year", "month", "day"};
    }

    static hash<DateTimeInfo> getNextMonthYear(int m, int y, list<int> l) {
        int bm;
        if (omq_inlist_sorted(m, l, \bm))
            return <DateTimeInfo>{"month": m, "year": y};

        if (exists bm)
            return <DateTimeInfo>{"month": bm, "year": y};

        # otherwise increment y and return the first month
        return <DateTimeInfo>{"month": l[0], "year": y + 1};
    }
}

class CronTimer {
    # no public members
    public {}

    private {
        # our trigger object
        AbstractTrigger trigger;
    }

    constructor(date recurring) {
        trigger = new RecurringTrigger(recurring);
    }

    constructor(int seconds) {
        trigger = new RecurringTrigger(seconds);
    }

    constructor(softstring minutes, softstring hours, softstring days, softstring months, softstring dow) {
        trigger = new CronTrigger(minutes, hours, days, months, dow);
    }

    string toString() {
        return trigger.toString();
    }

    # finds the next trigger time on or after the specified date
    date findNext(date d) {
        return trigger.findNext(d);
    }
}
