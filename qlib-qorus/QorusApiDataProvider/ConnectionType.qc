# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
    FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
    DEALINGS IN THE SOFTWARE.
*/

#! contains all public definitions in the QorusApiDataProvider module
public namespace QorusApiDataProvider {
#! connection type object
public const ConnectionType = new ConnectionType();
#! connection or nothing type object
public const ConnectionOrNothingType = new ConnectionOrNothingType();

#! Connection type
public class ConnectionType inherits WrapperType {
    #! Creates the object
    constructor() : WrapperType("connection", "softstring") {
    }
}

#! Connection or nothing type
public class ConnectionOrNothingType inherits WrapperType {
    #! Creates the object
    constructor() : WrapperType("*connection", "*softstring") {
    }
}
}
