# -*- mode: qore; indent-tabs-mode: nil -*-
# QorusObjectParserAPI.qc contains API for user to parse Qorus objects like service, job, mapper, vmap and others

#! Main namespace for the QorusObjectParser module
public namespace QorusObjectParser {

    /** QorusObjectParser::Parser class

        This class verifies metadata (tags) provided in the source file
        and parse the content to be potentially loaded into Qorus DB.
        @see @ref oload "oload" for more information

        Example of how the class can be used:
        @code{.py}
        QorusObjectParser::Parser parser(); # default encoding is utf8
        list<QorusObjectParser::QorusObject> objects = parser.parse("job1.qjob");
        parser.setEncoding(encoding) # to change the encoding
        objects += parser.parse(("job2.qjob", "job3.qjob"));
        @endcode
    */
    public class Parser {
        private {
            string encoding = "utf8";
        }
        public {
            static Logger logger;
        }

        #! Constructs the QorusObjectParser (default encoding is utf-8)
        constructor() {
            if (!logger) {
                # default logger with no appenders
                logger = new Logger("QorusObjectParser");
                Parser::logger.setLevel(Logger::LoggerLevel::INFO);
            }
        }

        #! sets logger for the QorusObjectParser
        /** @param logger
        */
        static setLogger(Logger logger) {
            Parser::logger = logger;
        }

        #! sets the encoding of the Parser
        /** @param encoding
        */
        setEncoding(string encoding) {
            self.encoding = encoding;
        }

        /* Parses the given service methods by file_iterator and returns a list of QorusObject
            @param file_path path to the file (used only for info)
            @param file_iterator line iterator to parse from
            @param class_based class-based flag
            @param lang qore or java language
            @throw QORUS-OBJECT-PARSER-ERROR in case of parse error
            @return list of QorusObject
        */
        list<QorusObject> parseServiceMethods(string file_path, AbstractLineIterator file_iterator, bool class_based,
                                              string lang) {
            TagParser tagParser = new ServiceMethodParser(file_path, True, 0, lang);
            tagParser.setEncoding(encoding);
            return tagParser.parse(file_iterator);
        }

        /* Parses the given file and returns a list of QorusObject
            @param file_path path to the file (can be absolute or relative)
            @throw QORUS-OBJECT-PARSER-ERROR in case of parse error
            @return list of QorusObject
        */
        list<QorusObject> parse(string file_path) {
            TagParser tagParser;
            switch (file_path) {
                case =~ /\.qfd$/:
                    tagParser = new FunctionParser(FunctionTags, file_path);
                    break;

                case =~ /\.qsd(.java)?$/:
                    tagParser = new ServiceParser(ServiceTags, file_path);
                    break;

                case =~ /\.qjob(.java)?$/:
                    tagParser = new JobParser(JobTags, file_path);
                    break;

                case =~ /\.qclass(.java)?$/:
                    tagParser = new TagParser("class", ClassTags, file_path);
                    break;

                case =~ /\.qmapper$/:
                    tagParser = new MapperParser(MapperTags, file_path);
                    break;

                case =~ /\.qvmap$/:
                    tagParser = new ValueMapParser(ValueMapTags, file_path);
                    break;

                case =~ /\.qconst$/:
                    tagParser = new TagParser("constant", ConstantTags, file_path);
                    break;

                default: throw "QORUS-OBJECT-PARSER-ERROR", sprintf("unknown extension of the file: %s", file_path);
            }

            tagParser.setEncoding(encoding);
            return tagParser.parse();
        }

        /* Parses the given files and returns a list of QorusObject
            @param file_paths list of file paths (can be absolute or relative)
            @return list of QorusObject
        */
        list<QorusObject> parse(list<string> file_paths) {
            list<QorusObject> result;
            foreach auto file_path in (file_paths) {
                result += parse(file_path);
            }
            return result;
        }
    }

    /* QorusObject class represents a parsed Qorus object.
       The class provides the information about it's metadata tags.
    */
    public class QorusObject {
        private {
            string type;
            hash tagDefinitions;
            hash tags;
            hash userTags;
        }

        /* QorusObject constructor
            @param type string type of the object
            @param tag_definitions tag definition hash of the object
            @param tags metada tags of the object as a hash
            @param user_tags user tags of the object
        */
        constructor(string type, hash tag_definitions, hash tags, hash user_tags) {
            self.type = type;
            self.tagDefinitions = tag_definitions;
            self.tags = tags;
            self.userTags = user_tags;
        }

        /* Serializes the QorusObject instance
        */
        hash<auto> serializeMembers() {
            return {
                "type": type,
                "tagDefinitions": tagDefinitions,
                "tags": tags,
                "userTags": userTags
            };
        }

        /* Returns allowed metadata tags for the QorusObject
            @return allowed metadata tags
        */
        list getAllowedTags() {
            return keys tagDefinitions;
        }

        /* Returns parsed metadata tags for the QorusObject
            @return hash with the parsed metadata tags
        */
        hash getTags() {
            return tags;
        }

        /* Returns metadata tag value for the QorusObject
            @param tag name of the tag
            @throw QORUS-OBJECT-ERROR in case the tag is invalid
            @return metadata tag value
        */
        auto getTag(string tag) {
            if (!tagDefinitions.hasKey(tag)) {
                 throw "QORUS-OBJECT-ERROR", sprintf("invalid tag: %s, allowed tags: %y", tag, getAllowedTags());
            }
            return tags{tag};
        }

        /* Member gate that returns metadata tag value for the QorusObject
            @param tag name of the tag
            @throw QORUS-OBJECT-ERROR in case the tag is invalid
            @return metadata tag value
        */
        auto memberGate(string tag) {
            return getTag(tag);
        }

        /* Returns parsed user tags for the QorusObject
            @return hash with the parsed user tags
        */
        hash getUserTags() {
            return userTags;
        }

        /* Returns object type
            @return object type as a string
        */
        string getType() {
            return type;
        }
    }
}
