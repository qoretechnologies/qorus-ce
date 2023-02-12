# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

#! main Qorus namespace
public namespace OMQ {
    const ProcessorKeyId = "_qorus_processor_key";

    const PipelineOptionKeys = (
        "input_provider_search",
        "input_search_options",
        "input_request",
        "input_request_options",
    );

    const PipelineOptions = Mapper::UserOptions{PipelineOptionKeys} + {
        "input_provider_bulk": <MapperOptionInfo>{
            "type": "int",
            "desc": "the number of records to use in a single bulk operation if both the pipeline and the provider "
                "support bulk operation",
        },
    };

    /**
        This class represents one pipeline factory in Qorus.
     */
    class QorusPipelineFactory inherits DataProviderPipelineFactory {
        private {
            hash<auto> pipeline;
            hash<auto> processors;
        }

        /**
            Constructs a QorusPipelineFactory with the given pipeline definition hash
            @param pipeline the pipeline info hash according to the YAML schema
         */
        constructor(hash<auto> pipeline)
            : DataProviderPipelineFactory(cast<*hash<PipelineOptionInfo>>(pipeline.options)) {
            self.pipeline = pipeline;
            constructPipeline(pipeline.children);
        }

        #! helper method to construct the pipeline (recursively if it contains queues)
        private constructPipeline(list<auto> children_, int queue_id = 0) {
%ifdef QorusServer
            foreach hash<auto> child in (children_) {
                if (child.type === "processor") {
                    Reflection::Class cls = getClassFromProcessor(child.name);
                    hash<auto> processor_tld = {
                        ProcessorKeyId: {
                            "name": pipeline.name,
                            "id": child.pid,
                        },
                    };
                    save_thread_data(processor_tld);
                    on_exit delete_thread_data(keys processor_tld);
                    # wrap all data processor objects to manage thread-local data correctly
                    QorusDataProcessorWrapper obj(cls.newObjectArgs(), processor_tld);
                    append(queue_id, obj);
                    if (child.children) {
                        constructPipeline(child.children, queue_id);
                    }
                } else if (child.type === "mapper") {
                    Mapper::Mapper mapper = get_specific_mapper(child.name);
                    append(queue_id, mapper);
                    if (child.children) {
                        constructPipeline(child.children, queue_id);
                    }
                } else if (child.type === "queue") {
                    int new_queue_id = appendQueue(queue_id);
                    constructPipeline(child.children, new_queue_id);
                }
            }
%endif
        }

        #! returns a class from cache if present or caches it from current interface program object
        private Reflection::Class getClassFromProcessor(string processor) {
            if (!processors.hasKey(processor)) {
                Program pgm = _priv_get_pgm_ctx();
                try {
                    processors{processor} = Reflection::Class::forName(pgm, processor);
                } catch (hash<ExceptionInfo> ex) {
                    throw ex.err, sprintf("pipeline %y: %s", pipeline.name, ex.desc), ex.arg;
                }
            }
            return processors{processor};
        }
    }

    class QorusDataProcessorWrapper inherits AbstractDataProcessor {
        private:internal {
            #! This is "object" so it can hold a Java object with the old API
            object obj;

            #! Thread-local data to set before running the processor
            *hash<auto> qorus_thread_local_data;

            #! Thread-local data keys from \a thread_local_data
            *list<string> qorus_thread_local_data_keys;
        }

        constructor(object obj, hash<auto> thread_local_data) {
            self.obj = obj;
            self.qorus_thread_local_data = thread_local_data;
            self.qorus_thread_local_data_keys = keys thread_local_data;
        }

        string className() {
            return obj.className();
        }

        private *AbstractDataProviderType getExpectedTypeImpl() {
            return obj.getExpectedType();
        }

        private *AbstractDataProviderType getReturnTypeImpl() {
            return obj.getReturnType();
        }

        private bool supportsBulkApiImpl() {
            return obj.supportsBulkApi();
        }

        private submitImpl(code enqueue, auto _data) {
            *hash<auto> tld;
            if (qorus_thread_local_data) {
                tld = get_all_thread_data();
                save_thread_data(qorus_thread_local_data);
            }
            on_exit if (qorus_thread_local_data) {
                delete_thread_data(qorus_thread_local_data_keys);
                save_thread_data(tld);
            }

            obj.submit(enqueue, _data);
        }

        private flushImpl(code enqueue) {
            # the old hardcoded Java classes have no "flush" methods
            if (obj.hasCallableMethod("flush")) {
                obj.flush(enqueue);
            }
        }
    }
}
