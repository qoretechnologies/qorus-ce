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
#! data provider type object
public const DataProviderType = new DataProviderType();
#! data provider or nothing type object
public const DataProviderOrNothingType = new DataProviderOrNothingType();

#! Data provider type
public class DataProviderType inherits WrapperType {
    #! Creates the object
    constructor() : WrapperType("data-provider", "string") {
    }
}

#! Data provider or nothing type
public class DataProviderOrNothingType inherits WrapperType {
    #! Creates the object
    constructor() : WrapperType("*data-provider", "*string") {
    }
}
}
