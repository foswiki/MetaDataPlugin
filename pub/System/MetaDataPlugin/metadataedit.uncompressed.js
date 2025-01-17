/*
 * MetaData Edit
 *
 * Copyright (c) 2011-2025 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL license http://www.gnu.org/licenses/gpl.html
 *
 */

/*global StrikeOne:false */

"use strict";
(function($) {

  var defaults = {
    pnotify: {
      text: "",
      type: "info",
      sticker: false,
      icon: false,
      closer_hover: true,
      animation: {
        effect_in: 'fade',
        effect_out: 'drop',
        options_out: {easing: 'easeOutCubic'}
      },
      animation_speed: 700,
      after_close: function() { }
    }
  };

  // class constructor
  function MetaDataEdit(elem, opts) {
    var self = this;

    self.elem = $(elem);
    self.opts = $.extend({}, defaults, opts);
    self.isModified = false;
    self.doReload = true;

    //console.log("called new for elem");

    if (self.elem.data("ui-dialog") === 'undefined') {
      self.elem.on("dialogopen", function() {
        self.init();
      });
    } else {
      self.init();
    }

    self.elem.on("dialogclose", function() {
      self.unlock();
    });
  }

  MetaDataEdit.prototype.unlock = function() {
    var self = this;

    $.jsonRpc(foswiki.getPreference("SCRIPTURL")+"/jsonrpc", {
      namespace: "MetaDataPlugin",
      method: "unlock",
      params: {
        "topic": self.topic
      },
      success: function() {
        //alert("done");
      },
      error: function(json) {
        self.notify({
          type: "error",
          text: json.error.message,
        });
      }
    });
  };

  MetaDataEdit.prototype.close = function() {
    var self = this;

    try {
      self.unlock();
      self.elem.dialog("destroy");
    } catch(err) {
      true;
    }

    self.elem.remove();
  };

  // init method called when dialog opened
  MetaDataEdit.prototype.init = function() {
    var self = this;

    self.widget = self.elem.dialog("widget"),

    self.widget.find(".jqUIDialogDestroy").on("click", function() {
      self.unlock();
      if (typeof(foswiki.eventClient) !== 'undefined') {
        foswiki.eventClient.send("cancel", {
          channel: self.topic
        });
      }
    });

    // get topic we are a metadata dialog for
    self.topic = self.opts.topic;
    if (typeof(self.topic) === 'undefined') {
      self.elem.find("[name='topic']:first").each(function() {
        self.topic = $(this).val();
      });
    }

    // monitor changes
    self.elem.find("[name]").on("change", function() {
      if (!self.isModified) {
        var uiTitle = self.widget.find(".ui-dialog-title");
        uiTitle.text(uiTitle.text()+" *");
        self.isModified = true;
      }
    });

    // ajaxify form
    self.form = self.elem.find("form");
    self.metadata = self.form.find("input[name='metadata']").val();

    if (foswiki.eventClient) {
      $("<input />").attr({
        type: "hidden",
        name: "clientId",
        value: foswiki.eventClient.id
      }).prependTo(self.form);
    }

    self.form.on("submit", function() {
      var deferreds = [];

      if (!self.form.validate().form()) {
        return false;
      }

      self.elem.block({message:""});
      if (typeof(StrikeOne) !== 'undefined') {
        StrikeOne.submit(self.form[0]);
      }

      // get values from natedit
      self.form.find(".natedit").each(function() {
        var textarea = $(this),
            editor = $(this).data("natedit");
        if (editor.engine) {
          deferreds.push(editor.engine.beforeSubmit("save"));
        }
      });

      $.when(...deferreds).then(function() {
        self.form.ajaxSubmit({
          complete: function() {
            self.form.trigger("done");
            window.setTimeout(function() {
              self.close();
            }, 100);
          },
          success: function() {
            if (typeof(foswiki.eventClient) === 'undefined') {
              self.notify({
                text: $.i18n("Saved metadata record"),
                type: "success"
              });
            }
            if (self.doReload) {
              //console.log("do reload",self.metadata);
              $(document).trigger("reload.metadata", self.metadata);
            } else {
              self.doReload = true;
            }
          },
          error: function() {
            self.notify({
              type: "error",
              text: $.i18n("There was an error saving a record."),
            });
          }
        });
      });

      return false;
    });

    // next and prev navigation
    self.widget.find(".metaDataNext, .metaDataPrev").on("click", function() {
      var sel = $(this).attr("selector"),
          button = $(".metaDataView .metaDataEditAction[data-metadata='"+self.metadata+"']").filter(function() {
            return $(this).data("metadata::name") === sel;
          });

      if (self.isModified) {
        self.doReload = false;
        self.form.trigger("submit").one("done", function() {
          button.trigger("click");
        });
      } else {
        button.trigger("click").one("opened", function() {
          window.setTimeout(function() {
            self.close();
          }, 100);
        });
      }

      return false;
    });
  };

  MetaDataEdit.prototype.notify = function(opts) {
    var self = this,
      thisOpts = $.extend({}, self.opts.pnotify, opts);

    $.pnotify(thisOpts);
  };

  // register to jquery
  $.fn.metaDataEdit = function (opts) { 
    return this.each(function() { 
      if (!$.data(this, "metaDataEdit")) { 
        $.data(this, "metaDataEdit", 
          new MetaDataEdit(this, opts)); 
        } 
    }); 
  };
 
  // document ready things
  $(function() {
    $(".metaDataEditDialog").livequery(function() {
      var $this = $(this),
          opts = $this.data();

      $this.metaDataEdit(opts);
    });
  });
})(jQuery);
