# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%require-types
%strict-args

# internal class that tells why something happened
class OMQ::ActionReason inherits Qore::Serializable {
    private {
        string who;
        string reason;
        string source;
        auto info;
        *hash<auto> cx;
    }

    private constructor() {
    }

    constructor(*hash<auto> cx, *string reason, bool override_reason = False) {
        if (cx || reason || override_reason)
            set(cx, reason, override_reason);
    }

    constructor(*hash<auto> cx, hash<auto> ex, *string err) {
        set(cx, ex, err);
    }

    bool isSet() {
        return exists reason;
    }

    clear() {
        map remove self.$1, keys self;
    }

    set(*hash<auto> cx, hash<auto> ex, *string err) {
        string reason;
        if (err)
            reason = err + "; ";
        reason += sprintf("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
        set(cx, reason, True);
    }

    set(string who, string reason, auto info, bool override = False) {
        # if information already set then return
        if (self.who && !override)
            return;
        self.who = who;
        self.reason = reason;
        self.info = info;
    }

    set(*hash<auto> cx, *string reason, bool override_reason = False) {
        if (override_reason) {
            if (reason)
                self.reason = reason;
            else
                delete self.reason;
        }
        if (!cx."peer-info" || cx.user == "%SYS%") {
            if (who) {
                return;
            }
            who = "Qorus";
            if (!self.reason) {
                if (!reason && cx.url.path && cx.rest_action_method) {
                    self.reason = sprintf("REST %s %s", cx.rest_action_method.upr(), cx.url.path);
                } else {
                    self.reason = reason ?? "internal API call";
                }
            }
            source = qorus_get_source();
            return;
        }
        self.cx = cx;

        source = cx."peer-info".address_desc;
        if (cx."peer-info".port)
            source += ":" + cx."peer-info".port;
        source += " listener: " + cx."socket-info".address_desc;
        if (cx."socket-info".port)
            source += ":" + cx."socket-info".port;
        who = cx.user ? cx.user : "Qorus";

        if (!self.reason) {
            if (cx.method)
                self.reason = "RPC: " + cx.method;
            else if (cx.orig_method) {
                self.reason = sprintf("REST %s %s", cx.hdr.method, cx.url.path);
                if (self.reason !~ /\?/)
                    self.reason += sprintf("?action=%s", cx.orig_method);
            } else
                self.reason = reason ?? "external API call";
        }
    }

    setReason(string reason) {
        self.reason = reason;
    }

    setReasonInfo(string reason, auto info) {
        self.reason = reason;
        self.info = info;
    }

    string getText() {
        return sprintf("%y", self.("reason", "who", "source", "info"));
    }

    string getReason() {
        return reason ? reason : "internal API call";
    }

    string getWho() {
        return who ?? "Qorus";
    }

    string getSource() {
        return source ?? "system";
    }

    hash<auto> getContext() {
        return cx ?? {"user": "%SYS%"};
    }
}

