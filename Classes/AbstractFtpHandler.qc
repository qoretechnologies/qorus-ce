# -*- mode: qore; indent-tabs-mode: nil -*-
# @file AbstractFtpHandler.qc provides the interface to the system's FTP server to service bindings

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%push-parse-options
%new-style

#! main Qorus namespace
public namespace OMQ {
#! this class is used to customize and control the behavior of Qorus FTP servers attached to services
/**
*/
public class AbstractFtpHandler {
    public {
        #! the root directory for file-based FTP servers
        /** if no value is set, then the file data will be passed to the fileDataReceived() method instead
        */
        *string root;

        #! if False (the default), then files are received as strings, if True, then as binary objects
        /** this only affects how file data is passed to the fileDataReceived() method
        */
        bool bin;

        #! list of listener info
        /** do not write to this list directly, use AbstractFtpHandler::addListener() instead (the internal format may
            change)
        */
        list<auto> listeners = ();

        #! authentication object
        HttpServer::AbstractAuthenticator auth;

        const MembersToSerialize = ("root", "bin", "listeners");
    }

    #! creates the object with the given arguments
    /** @param root the root directory for file-based FTP handlers; if this argument is not set, then the filesystem
        is not directly accessed by this object; instead data will be provided or requested directly (see
        fileDataReceived())
        @param bin if True then each file received will be read in as a binary object (only has an effect when no root
        directory is set)
        @param auth the HttpServer::AbstractAuthenticator for the object; if no argument is passed, then the system
        authenticator is used; meaning all users can connect without authentication

        @par Example:
        @code{.py}
class MyFtpHandler inherits public OMQ::AbstractFtpHandler {
    constructor() : AbstractFtpHandler("/opt/myftproot") {
    }
}
        @endcode
    */
    constructor(*string root, bool bin = False,
            HttpServer::AbstractAuthenticator auth = new DefaultQorusRBACAuthenticator()) {
        if (root) {
%ifdef Windows
            if (root =~ /\//)
                root = replace(root, "/", "\\");
            if (root !~ /\\$/)
                root += "\\";
%else
            if (root !~ /\/$/)
                root += "/";
%endif
        }
        self.root = root;
        self.bin = bin;
        self.auth = auth;

        logInfo("FTP handler root: %y bin: %y auth: %y", root, bin, auth);
    }

    hash<auto> getRemoteConfig() {
        return self{MembersToSerialize} + {
            # FIXME: need reflection
            # until we have reflection, this is a hack to see if the given methods are available in the current class
            # also this only partially works due to the way get_method_list() works, which returns the methods implemented
            # in the current class, but not of any parent classes, even if the methods are public
            "mh": (map {$1: True}, get_method_list(self)),
            "auth": (!exists auth ? "none" : (auth instanceof DefaultQorusRBACAuthenticator ? "def" : "remote")),
        };
    }

    string getUniqueHash() {
        string base = getUniqueHashBaseImpl();
        QDBG_LOG("AbstractFtpHandler::getUniqueHash() %y -> %y", base, base.toSHA512());
        return base.toSHA512();
    }

    private string getUniqueHashBaseImpl() {
        return sprintf("%s;%s;%s;%s", self.className(), root, bin.toString(), auth.className());
    }

    #! adds a listener from a port number; listener will start up on all interfaces on the given port
    /** @param port the port number to listen on; the listener will start up on all interfaces on the given port
      */
    addListener(int port) {
        listeners += port;
    }

    #! adds a listener from a bind string in the format: \c "address:port" (ex: \c "192.168.20.1:8011")
    /** @param bind the address:port string to bind the listener to
    */
    addListener(string bind) {
        listeners += bind;
    }

    #! adds a list of listeners from a list of bind addresses
    /** @param l list of listeners; each element should be either a bind string in the format: \c "address:port" (ex:
        \c "192.168.20.1:8011") or an integer port, meaning to bind on all interfaces on that port
    */
    addListeners(list<auto> l) {
        listeners += l;
    }

    #! this method is run when the server receives a \c "STOR" command from the client but before the server opens the data channel to receive the file
    /** @par Example:
        @code{.py}
class MyHandler inherits AbstractFtpHandler {
    # ...

    string authReceiveFile(string cwd, string orig, string path) {
        path += ".tmp";
        log(LoggerLevel::INFO, "authorizing receipt of file %s -> %s", path, path);
        return path;
    }
}
        @endcode

        @param cwd the current working directory
        @param orig the original literal argument passed by the client
        @param path the normalized path for the file that the client would like to send to the server; the actual file
        name can be changed by this method by returning a \c path key in the response value

        @return the actual path to use

        @throw FTP-RESPONSE-ERROR thrown if the argument has a value

        @note by default this method calls the authReceiveFile() variant taking a reference for backwards
        compatibility; set the exception \c arg value to an integer error code to override the default (\c 500)

        @since Qorus 5.0
    */
    string authReceiveFile(string cwd, string orig, string path) {
        checkCompatErrorResponse(authReceiveFile(cwd, orig, \path));
        return path;
    }

    #! this method is run when the server receives a \c "STOR" command from the client but before the server opens the data channel to receive the file; return no value if the server should accept the file, otherwise return a string that will be passed back to the client with a 500 error code rejecting the \c "STOR" request
    /** @param cwd the current working directory
        @param orig the original literal argument passed by the client
        @param path a reference to a string giving the normalized path for the file that the client would like to send
        to the server; the actual file name can be changed by this method by modifying the value of the reference (and
        returning NOTHING to authorize the receipt of the file)
        @return no value if the server will accept the file, otherwise return a string that will be passed back to the
        client with a 500 error code rejecting the \c "STOR" request; note that the default is to return no value and
        therefore accept the file from the client

        @par Example:
        @code{.py}
*string MyFtpHandler::authReceiveFile(string cwd, string orig, reference<string> path) {
    log(LoggerLevel::INFO, "authorizing receipt of file %s -> %s", path, path + ".tmp");
    path += ".tmp";
}
        @endcode
    */
    *string authReceiveFile(string cwd, string orig, reference<string> path) {
    }

    #! this method is called when the server has received a file and no root directory is set
    /** @param path the complete path of the file including the current working directory (starting from default "/" if the client did not issue any CWD commands) with the filename as given by the FTP client
        @param data the file data; will be a string if bin is False, otherwise it will be a binary object
        @see fileReceived()
    */
    fileDataReceived(string path, data data) {
    }

    #! this method is called when the server has received a file
    /** @param path the complete path of the file that was saved to the filesystem including the current working directory (starting from default "/" if the client did not issue any CWD commands) with the filename as given by the FTP client; the path does not include the FTP handler base directory, so a path of "/" is based in the top-level directory of root

        @par Example:
        @code{.py}
MyFtpHandler::fileReceived(string path) {
    ++stats."in".files;
    log(LoggerLevel::INFO, "received file: dir=%n fn=%n", dirname(path), basename(path));
}
        @endcode

        @see fileDataReceived()
    */
    fileReceived(string path) {
    }

    #! this method is run when the server receives a \c "RETR" command from the client but before the server opens the data channel to send the file
    /** @par Example:
        @code{.py}
class MyHandler inherits AbstractFtpHandler {
    # ...

    string authSendFile(string cwd, string orig, string path) {
        path += ".tmp";
        log(LoggerLevel::INFO, "authorizing sending of file %s -> %s", path, path);
        return path;
    }
}
        @endcode

        @param cwd the current working directory
        @param orig the original literal argument passed by the client
        @param path the normalized path for the file that the client would like to receive from the server; the actual file
        name can be changed by this method by returning a \c path key in the response value

        @return the actual path to use

        @throw FTP-RESPONSE-ERROR thrown if the argument has a value

        @note by default this method calls the authSendFile() variant taking a reference for backwards compatibility;
        set the exception \c arg value to an integer error code to override the default (\c 500)

        @since Qorus 5.0
    */
    string authSendFile(string cwd, string orig, string path) {
        checkCompatErrorResponse(authSendFile(cwd, orig, \path));
        return path;
    }

    #! this method is run when the server receives a \c "RETR" command from the client but before the server opens the data channel to receive the file; return no value if the server should accept the file, otherwise return a string that will be passed back to the client with a 500 error code rejecting the request
    /** @param cwd the current working directory
        @param orig the original literal argument passed by the client
        @param path a reference to a string giving the normalized path for the file that the client would like to receive from the server; the actual file name can be changed by this method by modifying the value of the reference (and returning NOTHING to authorize sending of the file)
        @return no value if the server will accept the file, otherwise return a string that will be passed back to the client with a 500 error code rejecting the \c "STOR" request; note that the default is to return no value and therefore accept the file from the client
    */
    *string authSendFile(string cwd, string orig, reference<string> path) {
    }

    #! this method is called when the server should send a file
    /** @param path the complete path of the file including the current working directory (starting from default "/") with the filename as given by the FTP client
        @return the file data to send
        @see fileReceived()
    */
    data sendFile(string path) {
        if (root) {
            string rp = getTargetPath(path);
            return ReadOnlyFile::readBinaryFile(rp);
        }
        return "";
    }

    #! this method is called when the \c "SIZE" command is received
    /** @param cwd the current working directory
        @param orig the original literal argument passed by the client
        @param path the complete path of the file including the current working directory (starting from default "/") with the filename as given by the FTP client

        @return the actual size to use

        @throw FTP-RESPONSE-ERROR thrown if the argument has a value; set the exception \c arg value to an integer
        error code to override the default (\c 550)

        @note by default this method calls the size() variant taking a reference for backwards compatibility

        @see sizeImpl()

        @since Qorus 5.0
    */
    int size(string cwd, string orig, string path) {
        int sze;
        checkCompatErrorResponse(size(cwd, orig, path, \sze));
        return sze;
    }

    #! this method is called when the \c "SIZE" command is received
    /** @param cwd the current working directory
        @param orig the original literal argument passed by the client
        @param path the complete path of the file including the current working directory (starting from default "/") with the filename as given by the FTP client
        @param size a reference to an int for the file size (output variable)

        @return an error message or @ref NOTHING for no error

        @throw FTP-RESPONSE-ERROR thrown if the argument has a value; set the exception \c arg value to an integer
        error code to override the default (\c 550)

        @note calls sizeImpl() for the actual logic

        @note methods with references have been deprecated, as lvalue references are not supported bewtween
        remote processes and also not in some other supported programming languages
    */
    *string size(string cwd, string orig, string path, reference<int> size) {
        size = sizeImpl(cwd, orig, path);
    }

    #! this method is called when the \c "SIZE" command is received
    /** @param cwd the current working directory
        @param orig the original literal argument passed by the client
        @param path the complete path of the file including the current working directory (starting from default "/") with the filename as given by the FTP client

        @return the file size to return to the FTP client
    */
    private int sizeImpl(string cwd, string orig, string path) {
        if (root) {
            string target_path = getTargetPath(path);
            *hash<StatInfo> h = hstat(target_path);
            if (!exists h) {
                throw "FTP-RESPONSE-ERROR", sprintf("%s: %s", orig, strerror());
            } else if (h.type != "REGULAR") {
                throw "FTP-RESPONSE-ERROR", sprintf("%s: not a plain file.", orig);
            }
            return h.size;
        }
        throw "FTP-RESPONSE-ERROR", "Not Implemented.";
    }

    #! this method is called when the \c "MDTM" command is received
    /** @param cwd the current working directory
        @param orig the original literal argument passed by the client
        @param path the complete path of the file including the current working directory (starting from default "/") with the filename as given by the FTP client

        @return the actual modified date to use

        @throw FTP-RESPONSE-ERROR thrown if the argument has a value; set the exception \c arg value to an integer
        error code to override the default (\c 550)

        @note by default this method calls the modifiedTime() variant taking a reference for backwards compatibility

        @see modifiedTimeImpl()

        @since Qorus 5.0
    */
    date modifiedTime(string cwd, string orig, string path) {
        date mdate;
        checkCompatErrorResponse(modifiedTime(cwd, orig, path, \mdate));
        return mdate;
    }

    #! this method is called when the \c "MDTM" command is received
    /** @param cwd the current working directory
        @param orig the original literal argument passed by the client
        @param path the complete path of the file including the current working directory (starting from default "/") with the filename as given by the FTP client
        @param mdate a reference to a date for the last modified date of the file (output variable)

        @return an error message or @ref NOTHING for no error

        @throw FTP-RESPONSE-ERROR thrown if the argument has a value; set the exception \c arg value to an integer
        error code to override the default (\c 550)

        @note calls modifiedTimeImpl() for the actual logic

        @note methods with references have been deprecated, as lvalue references are not supported bewtween
        remote processes and also not in some other supported programming languages
    */
    *string modifiedTime(string cwd, string orig, string path, reference<date> mdate) {
        mdate = modifiedTimeImpl(cwd, orig, path);
    }

    #! this method is called when the \c "MDTM" command is received
    /** @param cwd the current working directory
        @param orig the original literal argument passed by the client
        @param path the complete path of the file including the current working directory (starting from default "/") with the filename as given by the FTP client

        @return the file size to return to the FTP client

        @throw FTP-RESPONSE-ERROR thrown if the argument has a value; set the exception \c arg value to an integer
        error code to override the default (\c 500)
    */
    private date modifiedTimeImpl(string cwd, string orig, string path) {
        if (root) {
            string target_path = getTargetPath(path);
            *hash<StatInfo> h = hstat(target_path);
            if (!exists h) {
                throw "FTP-RESPONSE-ERROR", sprintf("%s: %s", orig, strerror());
            }
            return h.mtime;
        }
        throw "FTP-RESPONSE-ERROR", "Not Implemented.";
    }

    #! this method is called when the server has sent a file
    /** @param path the complete path of the file that was sent including the current working directory (starting from
        default "/") with the filename as given by the FTP client; the path does not include the FTP handler base
        directory, so a path of "/" is based in the top-level directory of root

        @see sendFile()
    */
    fileSent(string path) {
    }

    #! this method is run when the server receives a \c "CWD" command from the client but before the server updates the current working directory
    /**
        @par Example:
        @code{.py}
class MyHandler inherits AbstractFtpHandler {
    # ...

    string authChangeDir(string cwd, string orig, string path) {
        log(LoggerLevel::INFO, "cwd: %n orig: %n path: %n", cwd, orig, path);
        return AbstractFtpHandler::authChangeDirImpl(cwd, orig, path);
    }
}
        @endcode

        @param cwd the current working directory
        @param orig the original literal argument passed by the client
        @param path the normalized version of the directory name sent by the client (normalized means that it is a complete path from "/" without any references to ".." or ".")

        @return the actual path to use

        @throw FTP-RESPONSE-ERROR thrown if the argument has a value; set the exception \c arg value to an integer
        error code to override the default (\c 550)

        @note by default this method calls the authChangeDir() variant taking a reference for backwards compatibility

        @see authChangeDirImpl()

        @since Qorus 5.0
    */
    string authChangeDir(string cwd, string orig, string path) {
        checkCompatErrorResponse(authChangeDir(cwd, orig, \path));
        return path;
    }

    #! this method is run when the server receives a \c "CWD" command from the client but before the server updates the current working directory; return no value if the server should accept the change directory request, otherwise return a string that will be passed back to the client with a 550 error code rejecting the \c "CWD" request
    /** @param cwd the current working directory
        @param orig the original literal argument passed by the client
        @param path a reference to a string giving the normalized version of the directory name sent by the client
        (normalized means that it is a complete path from "/" without any references to ".." or "."); the actual
        directory name can be changed by this method by modifying the value of the reference (and returning NOTHING to
        authorize the change directory command)
        @return no value if the server will accept the change directory request, otherwise return a string that will
        be passed back to the client with a 550 error code rejecting the request; note that the default is to return
        no value and therefore accept the request

        @return an error message or @ref NOTHING for no error

        @throw FTP-RESPONSE-ERROR thrown if the argument has a value; set the exception \c arg value to an integer
        error code to override the default (\c 500)

        @note calls modifiedTimeImpl() for the actual logic

        @note methods with references have been deprecated, as lvalue references are not supported bewtween
        remote processes and also not in some other supported programming languages
    */
    *string authChangeDir(string cwd, string orig, reference<string> path) {
        path = authChangeDirImpl(cwd, orig, path);
    }

    #! this method is run when the server receives a \c "CWD" command from the client but before the server updates the current working directory
    /**
        @param cwd the current working directory
        @param orig the original literal argument passed by the client
        @param path the normalized version of the directory name sent by the client (normalized means that it is a
        complete path from "/" without any references to ".." or ".")

        @return the actual path to use

        @throw FTP-RESPONSE-ERROR thrown if the argument has a value; set the exception \c arg value to an integer
        error code to override the default (\c 550)
    */
    private string authChangeDirImpl(string cwd, string orig, string path) {
        if (root) {
            string target_path = getTargetPath(path);
            if (!is_dir(target_path)) {
                throw "FTP-RESPONSE-ERROR", sprintf("%s: No such file or directory.", orig);
            }
%ifdef Windows
            if (!is_readable(target_path)) {
                throw "FTP-RESPONSE-ERROR", sprintf("%s: Permission denied.", orig);
            }
%else
            if (!is_readable(target_path) || !is_executable(target_path)) {
                throw "FTP-RESPONSE-ERROR", sprintf("%s: Permission denied.", orig);
            }
%endif
            if (cwd == "/" && path == "..") {
                cwd = "/";
            }
            return path;
        }
        throw "FTP-RESPONSE-ERROR", "Not Implemented.";
    }

    #! this method is run when the server receives a \c "RNFR" command from the client
    /**
        @par Example:
        @code{.py}
class MyHandler inherits AbstractFtpHandler {
    # ...

    string authRename(string cwd, string orig, string path) {
        log(LoggerLevel::INFO, "cwd: %n orig: %n path: %n", cwd, orig, path);
        return AstractFtpHandler::authRenameImpl(cwd, orig, path);
    }
}
        @endcode

        @param cwd the current working directory
        @param orig the original literal argument passed by the client
        @param path a reference to a string giving the normalized version of the path (normalized means that it is a
        complete path from "/" without any references to ".." or "."); the actual path can be changed by this method
        by modifying the value of the reference (and returning NOTHING to authorize the command)

        @return the actual path to use

        @throw FTP-RESPONSE-ERROR thrown if the argument has a value; set the exception \c arg value to an integer
        error code to override the default (\c 550)

        @note by default this method calls the authRenameDir() variant taking a reference for backwards compatibility

        @see authChangeDirImpl()

        @since Qorus 5.0
    */
    string authRename(string cwd, string orig, string path) {
        checkCompatErrorResponse(authRename(cwd, orig, \path));
        return path;
    }

    #! this method is run when the server receives a \c "RNFR" command from the client; return no value if the server should accept the request, otherwise return a string that will be passed back to the client with a 550 error code rejecting the \c "RNFR" request
    /** @param cwd the current working directory
        @param orig the original literal argument passed by the client
        @param path a reference to a string giving the normalized version of the path (normalized means that it is a
        complete path from "/" without any references to ".." or "."); the actual path can be changed by this method
        by modifying the value of the reference (and returning NOTHING to authorize the command)

        @return an error message or @ref NOTHING for no error

        @throw FTP-RESPONSE-ERROR thrown if the argument has a value; set the exception \c arg value to an integer
        error code to override the default (\c 550)

        @note calls authRenameImpl() for the actual logic

        @note methods with references have been deprecated, as lvalue references are not supported bewtween
        remote processes and also not in some other supported programming languages
    */
    *string authRename(string cwd, string orig, reference<string> path) {
        path = authRenameImpl(cwd, orig, path);
    }

    #! this method is run when the server receives a \c "RNFR" command from the client
    /**
        @param cwd the current working directory
        @param orig the original literal argument passed by the client
        @param path a reference to a string giving the normalized version of the path (normalized means that it is a
        complete path from "/" without any references to ".." or "."); the actual path can be changed by this method
        by modifying the value of the reference (and returning NOTHING to authorize the command)

        @return the actual path to use

        @throw FTP-RESPONSE-ERROR thrown if the argument has a value; set the exception \c arg value to an integer
        error code to override the default (\c 550)

        @since Qorus 5.0
    */
    private string authRenameImpl(string cwd, string orig, string path) {
        if (root) {
            string target_path = getTargetPath(path);
            if (!exists hstat(target_path)) {
                throw "FTP-RESPONSE-ERROR", sprintf("%s: No such file or directory.", orig);
            }
            if (!is_readable(target_path)) {
                throw "FTP-RESPONSE-ERROR", sprintf("%s: Permission denied.", orig);
            }
            return path;
        }
        throw "FTP-RESPONSE-ERROR", "Not Implemented.";
    }

    #! this method is run when the server receives a \c "RNTO" command from the client; return no value if the server should accept the request (and thie method has already effected the rename of the file), otherwise return a string that will be passed back to the client with a 550 error code rejecting the request
    /** @par Example:
        @code{.py}
class MyHandler inherits AbstractFtpHandler {
    # ...

    *string rename(string cwd, string orig_to, string from, string to) {
        AbstractFtpHandler::rename(cwd, orig_to, from, to);
    }
}
        @endcode

        @param cwd the current working directory
        @param orig_to the original literal argument passed by the client
        @param from a string giving the normalized version of the "from" (source) path (normalized means that it is a
        complete path from "/" without any references to ".." or ".")
        @param to a string giving the normalized version of the "to" (target) path (normalized means that it is a
        complete path from "/" without any references to ".." or ".")

        @return no value if the server will accept the request, otherwise return a string that will be passed back to
        the client with a 550 error code rejecting the request; note that the default is to return no value and
        therefore accept the request

        @throw FTP-RESPONSE-ERROR thrown if the argument has a value; set the exception \c arg value to an integer
        error code to override the default (\c 550)
    */
    *string rename(string cwd, string orig_to, string from, string to) {
        return renameImpl(cwd, orig_to, from, to);
    }

    #! this method is run when the server receives a \c "RNTO" command from the client; return no value if the server should accept the request (and thie method has already effected the rename of the file), otherwise return a string that will be passed back to the client with a 550 error code rejecting the request
    /** @param cwd the current working directory
        @param orig_to the original literal argument passed by the client
        @param from a string giving the normalized version of the "from" (source) path (normalized means that it is a complete path from "/" without any references to ".." or ".")
        @param to a string giving the normalized version of the "to" (target) path (normalized means that it is a complete path from "/" without any references to ".." or ".")

        @throw FTP-RESPONSE-ERROR thrown if the argument has a value; set the exception \c arg value to an integer
        error code to override the default (\c 550)
    */
    private renameImpl(string cwd, string orig_to, string from, string to) {
        if (root) {
            string rfrom = getTargetPath(from);
            string rto = getTargetPath(to);
            try {
                Qore::rename(rfrom, rto);
            } catch (hash<ExceptionInfo> ex) {
                throw "FTP-RESPONSE-ERROR", sprintf("%s: %s.", orig_to, ex.desc);
            }
            return;
        }
        throw "FTP-RESPONSE-ERROR", "Not Implemented.";
    }

    #! this method is run when the server receives a \c "LIST" command from the client
    /** @param cwd the current working directory
        @param path the original literal argument passed by the client

        @return the output to return to the client

        @throw FTP-RESPONSE-ERROR thrown if the argument has a value; set the exception \c arg value to an integer
        error code to override the default (\c 550)

        @note by default this method calls the list() variant taking a reference for backwards compatibility

        @see listImpl()

        @since Qorus 5.0
    */
    string list(string cwd, *string path) {
        string output;
        checkCompatErrorResponse(list(cwd, path, \output));
        return output;
    }

    #! this method is run when the server receives a \c "LIST" command from the client; return no value and set the output reference if the server should accept the request, otherwise return a string that will be passed back to the client with a 550 error code rejecting the request
    /** @param cwd the current working directory
        @param path the original literal argument passed by the client
        @param output assign an output string to this reference for the output to be returned to the client

        @return an error message or @ref NOTHING for no error

        @throw FTP-RESPONSE-ERROR thrown if the argument has a value; set the exception \c arg value to an integer
        error code to override the default (\c 550)

        @note calls listImpl() for the actual logic

        @note methods with references have been deprecated, as lvalue references are not supported bewtween
        remote processes and also not in some other supported programming languages
    */
    *string list(string cwd, *string path, reference<string> output) {
        output = listImpl(cwd, path);
    }

    #! this method is run when the server receives a \c "LIST" command from the client
    /** @param cwd the current working directory
        @param path the original literal argument passed by the client

        @return the output to return to the client

        @throw FTP-RESPONSE-ERROR thrown if the argument has a value; set the exception \c arg value to an integer
        error code to override the default (\c 550)

        @since Qorus 5.0
    */
    private string listImpl(string cwd, *string path) {
        if (root) {
            path =~ s/-la//i;
            path =~ s/-al//i;
            path =~ s/-l//i;
            path =~ s/-a//i;
            string target_path = getTargetPath(cwd + path);
            try {
                #printf("list: rp=%n is_dir()=%n\n", target_path, is_dir(target_path));
                return is_dir(target_path)
                    ? AbstractFtpHandler::listDir(target_path)
                    : AbstractFtpHandler::listFile(target_path);
            } catch (hash<ExceptionInfo> ex) {
                throw "FTP-RESPONSE-ERROR", sprintf("%s: %s.", exists path, ex.desc);
            }
        }
        throw "FTP-RESPONSE-ERROR", "Not Implemented.";
    }

    #! this method is run when the server receives a \c "NLST" command from the client; return no value and set the output reference if the server should accept the request, otherwise return a string that will be passed back to the client with a 550 error code rejecting the request
    /** @par Example:
        @code{.py}
string MyFtpHandler::nlst(string cwd, *string path) {
    return AbstractFtpHandler::nlstImpl(cwd, path);
}
        @endcode

        @param cwd the current working directory
        @param path the original literal argument passed by the client

        @return the output to return to the client

        @throw FTP-RESPONSE-ERROR thrown if the argument has a value; set the exception \c arg value to an integer
        error code to override the default (\c 550)

        @note by default this method calls the nlst() variant taking a reference for backwards compatibility

        @see nlstImpl()

        @since Qorus 5.0
    */
    string nlst(string cwd, *string path) {
        string output;
        checkCompatErrorResponse(nlst(cwd, path, \output));
        return output;
    }

    #! this method is run when the server receives a \c "NLST" command from the client; return no value and set the output reference if the server should accept the request, otherwise return a string that will be passed back to the client with a 550 error code rejecting the request
    /** @param cwd the current working directory
        @param path the original literal argument passed by the client
        @param output assign an output string to this reference for the output to be returned to the client

        @return an error message or @ref NOTHING for no error

        @throw FTP-RESPONSE-ERROR thrown if the argument has a value; set the exception \c arg value to an integer
        error code to override the default (\c 550)

        @note calls nlstImpl() for the actual logic

        @note methods with references have been deprecated, as lvalue references are not supported bewtween
        remote processes and also not in some other supported programming languages
    */
    *string nlst(string cwd, *string path, reference<string> output) {
        output = nlstImpl(cwd, path);
    }

    #! this method is run when the server receives a \c "NLST" command from the client; return no value and set the output reference if the server should accept the request, otherwise return a string that will be passed back to the client with a 550 error code rejecting the request
    /**
        @param cwd the current working directory
        @param path the original literal argument passed by the client

        @return the output to return to the client

        @throw FTP-RESPONSE-ERROR thrown if the argument has a value; set the exception \c arg value to an integer
        error code to override the default (\c 550)

        @since Qorus 5.0
    */
    private string nlstImpl(string cwd, *string path) {
        if (root) {
            list<string> l = split(" ", path);
            bool found = False;
            for (int i = 0; i < elements l; ++i) {
                if (l[i] !~ /^-/) {
                    found = True;
                    l[i] = getTargetPath(cwd + l[i]);
                    break;
                }
            }

            if (!found) {
                l += getTargetPath(cwd);
            }

            string target_path = join(" ", l);

            try {
                string cmd = sprintf("/bin/ls -a %s 2>&1", target_path);
                #QDBG_LOG("FTP NLST: path: %y, cmd: %y nl: %y", path, cmd, l);
                return replace(backquote(cmd), "\n", "\r\n");
            } catch (hash<ExceptionInfo> ex) {
                throw "FTP-RESPONSE-ERROR", sprintf("%s: %s.", path, ex.desc);
            }
        }
        throw "FTP-RESPONSE-ERROR", "Not Implemented.";
    }

    #! this method is run when the server receives a \c "MLST" command from the client
    /** @param cwd the current working directory
        @param orig the original literal argument passed by the client
        @param path a string giving the normalized version of the path argument (normalized means that it is a complete path from "/" without any references to ".." or ".")

        @return the output to return to the client

        @throw FTP-RESPONSE-ERROR thrown if the argument has a value; set the exception \c arg value to an integer
        error code to override the default (\c 550)

        @note by default this method calls the nlst() variant taking a reference for backwards compatibility

        @see machineListFileImpl()

        @since Qorus 5.0
    */
    string machineListFile(string cwd, *string orig, string path) {
        string output;
        checkCompatErrorResponse(machineListFile(cwd, orig, path, \output));
        return output;
    }

    #! this method is run when the server receives a \c "MLST" command from the client; return no value and set the output reference if the server should accept the request, otherwise return a string that will be passed back to the client with a 550 error code rejecting the request
    /** @param cwd the current working directory
        @param orig the original literal argument passed by the client
        @param path a string giving the normalized version of the path argument (normalized means that it is a complete path from "/" without any references to ".." or ".")
        @param output assign an output string to this reference for the output to be returned to the client

        @return an error message or @ref NOTHING for no error

        @throw FTP-RESPONSE-ERROR thrown if the argument has a value; set the exception \c arg value to an integer
        error code to override the default (\c 550)

        @note calls machineListFileImpl() for the actual logic

        @note methods with references have been deprecated, as lvalue references are not supported bewtween
        remote processes and also not in some other supported programming languages
    */
    *string machineListFile(string cwd, *string orig, string path, reference<string> output) {
        output = machineListFileImpl(cwd, orig, path);
    }

    #! this method is run when the server receives a \c "MLST" command from the client
    /** @param cwd the current working directory
        @param orig the original literal argument passed by the client
        @param path a string giving the normalized version of the path argument (normalized means that it is a complete path from "/" without any references to ".." or ".")

        @return the output to return to the client

        @throw FTP-RESPONSE-ERROR thrown if the argument has a value; set the exception \c arg value to an integer
        error code to override the default (\c 550)

        @since Qorus 5.0
    */
    private string machineListFileImpl(string cwd, *string orig, string path) {
        if (root) {
            string target_path = getTargetPath(path);
            #ServiceApi::logDebug("machineListFile() path: %y tp: %y", path, target_path);
            string output = AbstractFtpHandler::getMLSx(orig, target_path, True);
            splice output, 0, 0, " ";
            return output;
        }
        throw "FTP-RESPONSE-ERROR", "Not Implemented.";
    }

    #! this method is run when the server receives a \c "MLSD" command from the client
    /** @param cwd the current working directory
        @param orig the original literal argument passed by the client
        @param path a string giving the normalized version of the path argument (normalized means that it is a complete path from "/" without any references to ".." or ".")

        @return the output to return to the client

        @throw FTP-RESPONSE-ERROR thrown if the argument has a value; set the exception \c arg value to an integer
        error code to override the default (\c 501 or \c 550)

        @note by default this method calls the machineListDir() variant taking a reference for backwards compatibility

        @see machineListDirImpl()

        @since Qorus 5.0
    */
    string machineListDir(string cwd, *string orig, string path) {
        string output;
        checkCompatErrorResponse(machineListDir(cwd, orig, path, \output));
        return output;
    }

    #! this method is run when the server receives a \c "MLSD" command from the client; return no value and set the output reference if the server should accept the request, otherwise return a string that will be passed back to the client with a 550 error code rejecting the request
    /** @param cwd the current working directory
        @param orig the original literal argument passed by the client
        @param path a string giving the normalized version of the path argument (normalized means that it is a complete path from "/" without any references to ".." or ".")
        @param output assign an output string to this reference for the output to be returned to the client
        @param isdir if False on output and there is an error response, then a 501 code will be generated instead of a 550 code

        @return no value if the server will accept the request, otherwise return a string that will be passed back to the client with a 550 error code rejecting the request; note that the default is to return no value
    */
    *string machineListDir(string cwd, *string orig, string path, *reference<string> output, *reference<bool> isdir) {
        output = machineListDirImpl(cwd, orig, path);
    }

    #! this method is run when the server receives a \c "MLSD" command from the client
    /** @param cwd the current working directory
        @param orig the original literal argument passed by the client
        @param path a string giving the normalized version of the path argument (normalized means that it is a complete path from "/" without any references to ".." or ".")

        @return the output to return to the client

        @throw FTP-RESPONSE-ERROR thrown if the argument has a value; set the exception \c arg value to an integer
        error code to override the default (\c 501 or \c 550)

        @since Qorus 5.0
    */
    private string machineListDirImpl(string cwd, *string orig, string path) {
        if (root) {
            string target_path = getTargetPath(path);
            #ServiceApi::logDebug("machineListDir() path: %y tp: %y", path, target_path);
            if (!is_dir(target_path)) {
                throw "FTP-RESPONSE-ERROR", "Not a directory.", 501;
            }

            Dir dir();

            if (!dir.chdir(target_path)) {
                throw "FTP-RESPONSE-ERROR", "No such file or directory.";
            }

            return (foldl $1 + $2, (map AbstractFtpHandler::getMLSx(orig, target_path + "/" + $1), ((".", "..") + dir.list()))) ?? "";
        }
        throw "FTP-RESPONSE-ERROR", "Not Implemented.";
    }

    #! returns the real path on the filesystem for the given virtual path
    string getTargetPath(string path) {
%ifdef Windows
        if (path =~ /\//)
            path = replace(path, "/", "\\");
        if (path =~ /^\\+/)
            path =~ s/^\\+//;
%else
        if (path =~ /^\/+/)
            path =~ s/^\/+//;
%endif
        return normalize_dir(root + path);
    }

    #! this method is run when the server receives a \c "MKD" command from the client; return no value if the server should accept the request, otherwise return a string that will be passed back to the client with a 550 error code rejecting the request
    /** @par Example:
        @code{.py}
class MyFtpHandler {
    # ...

    *string makeDir(string cwd, string orig, string path) {
        AbstractFtpHandler::makeDirImpl(cwd, orig, path);
    }
}
        @endcode

        @param cwd the current working directory
        @param orig the original literal argument passed by the client
        @param path a string giving the normalized version of the path (normalized means that it is a complete path
        from "/" without any references to ".." or ".")

        @return no value if the server will accept the request, otherwise return a string that will be passed back to
        the client with a 550 error code rejecting the request; note that the default is to return no value and
        therefore accept the request

        @throw FTP-RESPONSE-ERROR thrown if the argument has a value; set the exception \c arg value to an integer
        error code to override the default (\c 550)
    */
    *string makeDir(string cwd, string orig, string path) {
        makeDirImpl(cwd, orig, path);
    }

    #! this method is run when the server receives a \c "MKD" command from the client; return no value if the server should accept the request, otherwise return a string that will be passed back to the client with a 550 error code rejecting the request
    /** @param cwd the current working directory
        @param orig the original literal argument passed by the client
        @param path a string giving the normalized version of the path (normalized means that it is a complete path
        from "/" without any references to ".." or ".")

        @throw FTP-RESPONSE-ERROR thrown if the argument has a value; set the exception \c arg value to an integer
        error code to override the default (\c 550)

        @since Qorus 5.0
    */
    private makeDirImpl(string cwd, string orig, string path) {
        if (root) {
            string target_path = getTargetPath(path);
            int rc = mkdir(target_path);
            if (rc) {
                #log(LoggerLevel::INFO, "mkdir(cwd: %y orig: %y path: %y root: %y rp: %y): %s", cwd, orig, path, root, target_path, strerror());
                throw "FTP-RESPONSE-ERROR", sprintf("%s: %s.", orig, strerror());
            }
            return;
        }
        throw "FTP-RESPONSE-ERROR", "Not Implemented.";
    }

    #! this method is run when the server receives a \c "RMD" command from the client; return no value if the server should accept the request, otherwise return a string that will be passed back to the client with a 550 error code rejecting the request
    /** @par Example:
        @code{.py}
class MyFtpHandler {
    # ...

    *string removeDir(string cwd, string orig, string path) {
        AbstractFtpHandler::removeDirImpl(cwd, orig, path);
    }
}
        @endcode

        @param cwd the current working directory
        @param orig the original literal argument passed by the client
        @param path a string giving the normalized version of the path (normalized means that it is a complete path
        from "/" without any references to ".." or ".")

        @return no value if the server will accept the request, otherwise return a string that will be passed back to
        the client with a 550 error code rejecting the request; note that the default is to return no value and
        therefore accept the request

        @throw FTP-RESPONSE-ERROR thrown if the argument has a value; set the exception \c arg value to an integer
        error code to override the default (\c 550)
    */
    *string removeDir(string cwd, string orig, string path) {
        removeDirImpl(cwd, orig, path);
    }

    #! this method is run when the server receives a \c "RMD" command from the client; return no value if the server should accept the request, otherwise return a string that will be passed back to the client with a 550 error code rejecting the request
    /** @param cwd the current working directory
        @param orig the original literal argument passed by the client
        @param path a string giving the normalized version of the path (normalized means that it is a complete path
        from "/" without any references to ".." or ".")

        @throw FTP-RESPONSE-ERROR thrown if the argument has a value; set the exception \c arg value to an integer
        error code to override the default (\c 550)

        @since Qorus 5.0
    */
    private removeDirImpl(string cwd, string orig, string path) {
        if (root) {
            string target_path = getTargetPath(path);
            int rc = rmdir(target_path);
            if (rc) {
                throw "FTP-RESPONSE-ERROR", sprintf("%s: %s (%y).", orig, strerror(), target_path);
            }
            return;
        }
        throw "FTP-RESPONSE-ERROR", "Not Implemented.";
    }

    #! this method is run when the server receives a \c "DELE" command from the client; return no value if the server should accept the request, otherwise return a string that will be passed back to the client with a 550 error code rejecting the request
    /** @par Example:
        @code{.py}
class MyFtpHandler {
    # ...

    *string deleteFile(string cwd, string orig, string path) {
        AbstractFtpHandler::removeDirImpl(cwd, orig, path);
    }
}
        @endcode

        @param cwd the current working directory
        @param orig the original literal argument passed by the client
        @param path a string giving the normalized version of the path (normalized means that it is a complete path from "/" without any references to ".." or ".")

        @return no value if the server will accept the request, otherwise return a string that will be passed back to the client with a 550 error code rejecting the request; note that the default is to return no value and therefore accept the request

        @throw FTP-RESPONSE-ERROR thrown if the argument has a value; set the exception \c arg value to an integer
        error code to override the default (\c 550)
    */
    *string deleteFile(string cwd, string orig, string path) {
        deleteFileImpl(cwd, orig, path);
    }

    #! this method is run when the server receives a \c "DELE" command from the client
    /** @param cwd the current working directory
        @param orig the original literal argument passed by the client
        @param path a string giving the normalized version of the path (normalized means that it is a complete path
        from "/" without any references to ".." or ".")

        @return no value if the server will accept the request

        @throw FTP-RESPONSE-ERROR thrown if the argument has a value; set the exception \c arg value to an integer
        error code to override the default (\c 550)

        @since Qorus 5.0
    */
    private deleteFileImpl(string cwd, string orig, string path) {
        if (root) {
            string target_path = getTargetPath(path);
            int rc = unlink(target_path);
            if (rc) {
                throw "FTP-RESPONSE-ERROR", sprintf("%s: %s.", orig, strerror());
            }
            return;
        }
        throw "FTP-RESPONSE-ERROR", "Not Implemented.";
    }

    #! writes the message to the service log file if the log level is equal or lower
    /** @since Qorus 4.1.2
    */
    logFatal(softstring msg) {
        ServiceApi::logArgsFatal(msg, argv);
    }

    #! writes the message to the service log file if the log level is equal or lower
    /** @since Qorus 4.1.2
    */
    logError(softstring msg) {
        ServiceApi::logArgsError(msg, argv);
    }

    #! writes the message to the service log file if the log level is equal or lower
    /** @since Qorus 4.1.2
    */
    logWarn(softstring msg) {
        ServiceApi::logArgsWarn(msg, argv);
    }

    #! writes the message to the service log file if the log level is equal or lower
    /** @since Qorus 4.1.2
    */
    logInfo(softstring msg) {
        ServiceApi::logArgsInfo(msg, argv);
    }

    #! writes the message to the service log file if the log level is equal or lower
    /** @since Qorus 4.1.2
    */
    logDebug(softstring msg) {
        ServiceApi::logArgsDebug(msg, argv);
    }

    #! writes the message to the service log file if the log level is equal or lower
    /** @since Qorus 4.1.2
    */
    logTrace(softstring msg) {
        ServiceApi::logArgsTrace(msg, argv);
    }

    # document!
    static *string getMLSx(*string orig, string path, bool dir = False) {
        *hash<StatInfo> h = hstat(path);
        if (!exists h) {
            throw "FTP-RESPONSE-ERROR", sprintf("%s: %s.", exists orig ? orig : path, strerror());
        }

        string name = path != "/" ? basename(path) : "/";

        string str = "Type=";
        if (h.type == "DIRECTORY") {
            str += dir ? "cdir" : (name == ".." ? "pdir" : (name == "." ? "cdir" : "dir"));
        } else if (h.type == "BLOCK-DEVICE") {
            hash<auto> dev = AbstractFtpHandler::getDevice(h.rdev);
            str += sprintf("OS.unix=blk-%d/%d", dev.major, dev.minor);
        } else if (h.type == "CHAR-DEVICE") {
            hash<auto> dev = AbstractFtpHandler::getDevice(h.rdev);
            str += sprintf("OS.unix=chr-%d/%d", dev.major, dev.minor);
        } else {
            str += sprintf("file;Size=%d", h.size);
        }
        # FIXME: check pipes, sockets

        str += sprintf(";Modify=%s", gmtime(h.mtime).format("YYYYMMDDHHmmSS"));

        # do Perm
        #str += sprintf(";Perm=%s", "ceflmp");

        # do Unique
        str += sprintf(";Unique=%010d", h.inode);

        # add name
        str += sprintf("; %s\r\n", name);

        return str;
    }

    static hash<auto> getDevice(int rdev) {
        return {
            "major": (rdev & 0xff000000) >> 24,
            "minor": (rdev & 0x00ffffff),
        };
    }

    static *string listFile(string target_path, reference<string> output) {
        output = AbstractFtpHandler::listFile(target_path);
    }

    static string listFile(string target_path) {
        *hash<auto> h = hstat(target_path);
        if (!h) {
            throw "FTP-RESPONSE-ERROR", sprintf("%s: %s", target_path, strerror());
        }

        string time = format_date("Mon DD ", h.mtime);
        if (now_us() - h.mtime > 6M) {
            time += format_date(" YYYY", h.mtime);
        } else {
            time += format_date("HH:mm", h.mtime);
        }

        return sprintf("%s %4d %-8s %-8s %8d %s %s\r\n", h.perm, h.nlink, h.uid, h.gid, h.size, time, basename(target_path));
    }

    static *string listDir(string target_path, reference<string> output) {
        output = AbstractFtpHandler::listDir(target_path);
    }

    static string listDir(string target_path) {
        *list<string> l = glob(target_path + "/*");
        l = elements l ? (".", "..") + l : (".", "..");
        return (foldl $1 + $2, (map AbstractFtpHandler::listFile($1), l)) ?? "";
    }

    #! Checks for an error response and throws an \c FTP-RESPONSE-ERROR exception if found
    /** @throw FTP-RESPONSE-ERROR thrown if the argument has a value

        @since Qorus 5.0
    */
    static private checkCompatErrorResponse(*string errstr) {
        if (errstr) {
            throw "FTP-RESPONSE-ERROR", errstr;
        }
    }
}
}
