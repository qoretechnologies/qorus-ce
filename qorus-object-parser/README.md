# Qorus Object Parser Module

Module for parsing Qorus object files.

**Supported file extensions:**

* .qfd
* .qsd
* .qsd.java
* .qjob
* .qjob.java
* .qclass
* .qclass.java
* .qmapper
* .qvmap
* .qconst

## QorusObjectParser::Parser class
### Example

```python
list<QorusObjectParser::QorusObject> objects = parser.parse("job1.qjob");
QorusObjectParser::Parser parser(); # default encoding is utf8
parser.setEncoding(encoding) # to change the encoding
objects += parser.parse(("job2.qjob", "job3.qjob"));
```

# Qyaml Module

Module for parsing and validating Qorus object files in the YAML format.

## Parsing

The following functions can be used to parse a Qorus object in the YAML format:


1) Parse the given list of YAML files:
    ```java
    @param file_paths list of YAML files
    @throw QYAML-ERROR in case YAML is empty or in case the given file has syntax errors
    public list sub parse(list<string> file_paths) {
    ```
2) Parse the given YAML file:
    ```java
    @param file_path path to the YAML file
    @throw QYAML-ERROR in case YAML is empty or file extension is incorrect
    @throw YAML-PARSER-ERROR in case the given file has syntax errors
    public auto sub parse_yaml_file(string file_path)
    ```

**Supported extensions:**
* .yaml
* .yml


## Validation

**Supported Qorus Objects:**

* job
* service
* workflow
* function
* class
* constant
* mapper
* connection
* value
* queue
* event
* group

### create_validator function

This helper function creates a validator object based on the given type:

```java
@param type one of the KnownObjects
@throw QYAML-ERROR in case type is unknown or schema is empty
public Validator sub create_validator(string type)
```

### Validator class

An object of the class should be constructed using the above function (create_validator).

The class provides the following method for the validation:
```java
@param parsed_yaml parsed YAML data as a hash
@throw QYAML-VALIDATOR-ERROR in case validation has failed
validate(string path, ParsedYaml parsed_yaml)
```