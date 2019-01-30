FOSWIKI_ROOT?=~/foswiki/trunk/core
TARGET=metadata.css metadata.js

SOURCE=metadataview.uncompressed.js metadataedit.uncompressed.js

-include $(FOSWIKI_ROOT)/pub/System/JQueryPlugin/Makefile.include

metadata.uncompressed.js: $(SOURCE)
	@echo generating $@
	@$(CAT) $^ > $@

clean:
	rm -f $(TARGET) *.gz *.map metadata.uncompressed.js

