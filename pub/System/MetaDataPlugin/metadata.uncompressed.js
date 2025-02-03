/*
 * MetaData View
 *
 * Copyright (c) 2011-2025 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL license http://www.gnu.org/licenses/gpl.html
 *
 */
"use strict";
(function($) {

  var defaults = {
      hideActionDelay: 1500
    };

  // class constructor
  function MetaDataView(elem, opts) {
    var self = this;

    self.elem = $(elem);
    self.opts = $.extend({}, defaults, self.elem.data(), opts);

    //console.log("called new",self);

    self.init();
  }

  // show actions 
  MetaDataView.prototype.showActions = function($row) {
    var self = this;

    self.elem.find(".hover").removeClass("hover");
    $row.addClass("hover");
  };

  // hide actions 
  MetaDataView.prototype.hideActions = function() {
    var self = this;

    self.elem.find(".hover").removeClass("hover");
  };

  // adds a hide-action timer
  MetaDataView.prototype.startTimer = function() {
    var self = this;
    self.timeout = setTimeout(function() {
      if (!self.active) {
        self.hideActions();
      }
    }, self.opts.hideActionDelay);
  };

  // replace this with a newly reloaded version
  MetaDataView.prototype.reload = function() {
    var self = this,
        data = $.parseJSON(self.elem.find(".metaDataParams").html());

    data.name = "RENDERMETADATA";
    data.param = self.opts.metadata;
    data.web = data.web || foswiki.getPreference("WEB");
    data.topic = data.topic || foswiki.getPreference("TOPIC");
    data.topic = data.web + "." + data.topic;
    data.render= "on";

    //console.log("reload", data);

    return $.ajax({
      url: foswiki.getScriptUrl("rest", "RenderPlugin", "tag"),
      type: "POST",
      data: data
    }).then(function(response) {
      var newElem = $(response).hide();
      self.elem.replaceWith(newElem);
      newElem.fadeIn();
      $(document).trigger("afterReload.metadata", self.opts.metadata);
    });
  };


  // init method
  MetaDataView.prototype.init = function() {
    var self = this;
    
    self.active = false;

    self.elem.find(".metaDataActions").on("mouseenter", function() {
      self.active = true;
    }).on("mouseleave", function() {
      self.active = false;
      self.startTimer();
    });

    self.elem.on("mouseenter", ".metaDataRow, tbody tr", function() {
      var $row = $(this), 
          $actions = $row.find(".metaDataActions");

      if ($actions.length) {
        self.active = true;
        if (self.timeout) {
          clearTimeout(self.timeout);
        }
        self.showActions($row);
      }
    }).on("mouseleave", ".metaDataRow, tbody tr", function() {
      self.active = false;
      self.startTimer();
    }).on("dblclick", ".metaDataRow, tbody tr", function(e) {
      var $this = $(this), 
          $editAction = $this.find(".metaDataEditAction");

      if (self.elem.is(".metaDataReadOnly")) {
        return;
      }

      //$this.effect("highlight"); // broken

      if ($(e.target).is(".metaDataRow, td")) {
        self.elem.find("tr").removeClass("selected");
        $this.addClass("selected");

        if ($editAction.length) {
          $editAction.trigger("click");
          return false;
        }
      }
    }).on("click", ".metaDataEditAction", function() {
      var $this = $(this),
          opts = $this.data(),
          row = $this.parents("tr, .metaDataRow").first(),
          next = row.next(),
          prev = row.prev(),
          webTopic = foswiki.normalizeWebTopicName(foswiki.getPreference("WEB"), opts.topic);

      opts["metadata::prev"] = prev.find(".metaDataEditAction").data("metadata::name");
      opts["metadata::next"] = next.find(".metaDataEditAction").data("metadata::name");

      _loadDialog(opts).then(function() {
        if (foswiki.eventClient) {
          foswiki.eventClient.send("edit", {
            channel: opts.topic,
            web: webTopic[0],
            topic: webTopic[1]
          });
        }
        $this.trigger("opened");
      });

      return false;
    }).on("click", ".metaDataViewAction", function() {
      var $this = $(this),
          opts = $this.data(),
          row = $this.parents("tr, .metaDataRow").first(),
          next = row.next(),
          prev = row.prev();

      opts["metadata::prev"] = prev.find(".metaDataViewAction").data("metadata::name");
      opts["metadata::next"] = next.find(".metaDataViewAction").data("metadata::name");

      _loadDialog(opts).then(function() {
        $this.trigger("opened");
      });

      return false;
    });
    
    $(document).on("reload.metadata", function(ev, metadata) {
      if (typeof(self.opts.metadata === 'undefined') || self.opts.metadata === metadata) {
        self.reload();
      }
    });

    self.elem.find("tbody").sortable({
      items: "> tr",
      cursor: "move",
      handle: ".metaDataMoveAction",
      forcePlaceholderSize: true,
      placeholder: "metaDataPlaceholder",
      /*axis: "y",*/
      helper: function(e, ui) {
        /* preserve width */
        ui.children().each(function() {
            var $this = $(this);
            $this.width($this.width());
        });
        return ui;
      },
      stop: function(e, ui) {
        /* undo local width */
        ui.item.children().each(function() {
          $(this).css("width", "");
        });
      }
    });

  };

  // dialog loader
  function _loadDialog(opts) {
    return foswiki.loadTemplate(opts).then(function(data, status, xhr) {
      var nonce = xhr.getResponseHeader("X-Foswiki-Validation"),
          $content = $(data.expand);

      if (typeof(nonce) !== 'undefined') {
        $content.find("form").each(function() {
          var $form = $(this),
              $input = $form.find("[name='validation_key']"),
              metadata = $form.find("[name='metadata']").val();

          if (!$input.length) {
            $input = $("<input type='hidden' name='validation_key' />").prependTo($form);
          }
          $input.val("?"+nonce);

        });
      }

      $content.hide().appendTo("body").data("autoOpen", true);
    });
  }

  // register to jquery
  $.fn.metaDataView = function (opts) { 
    return this.each(function() { 
      var $this = $(this);
      if (!$this.data("metaDataView")) { 
        $this.data("metaDataView", new MetaDataView(this, opts)); 
      } 
    }); 
  };
 
  // document ready things
  $(function() {
    $(document).on("click", ".metaDataNewAction", function() {
      var $this = $(this), opts = $this.data();

      _loadDialog(opts).then(function() {
        $this.trigger("opened");
      });
    });

    $(".metaDataView").livequery(function() {
      $(this).metaDataView();
    });

    $(".metaDataDeleteDialog").livequery(function() {
      var $dialog = $(this),
          $form = $dialog.find("form"),
          metadata = $form.find("[name='metadata']").val();

      $form.ajaxForm({
        success: function() {
          $(document).trigger("reload.metadata", metadata);
        },
        complete: function() {
          $dialog.dialog("destroy");
          $.pnotify({
            text: $.i18n("Metadata record deleted"),
            type: "success"
          });
        },
        error: function() {
          $.blockUI({
            message: '<h2 class="i18n">Warning</h2><div class="i18n">This topic is locked. <br />Please try again later.</div>',
            timeout: 3000,
            onBlock: function() {
              $('.blockUI').click(function() {
                $.unblockUI(); 
                return false;
              });
            }
          });
        }
      });
    });
  });

  $.validator.addClassRules("foswikiMandatory", {
    required: true
  });

})(jQuery);
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
/*
 * MetaData Buttons
 *
 * Copyright (c) 2019-2025 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL license http://www.gnu.org/licenses/gpl.html
 *
 */
"use strict";
(function($) {
   $(document).on("click", ".metaDataImport", function() {
      var $this = $(this), opts = $this.data();
      //console.log("clicked metadata import", opts);

      $.blockUI({message: "<h2>"+$.i18n("Importing ...")+"</h2>"});

      $.jsonRpc(foswiki.getScriptUrl("jsonrpc", "MetaDataPlugin", "import"), {
         params: opts
      }).done(function(data) {
         var msg, type = "success";
         
         $.unblockUI();
         //console.log("data=",data);
         
         if (data.result > 0) {
            msg = $.i18n("Updated %count% record(s)", {count: data.result});
         } else {
            msg = $.i18n("No records updated");
            type = "info";
         }
         
         $.pnotify({
            title: $.i18n("Success"),
            text: msg,
            type: type
         });
         
         if (data.result > 0) {
            $.blockUI({message: "<h2>"+$.i18n("Reloading ...")+"</h2>"});
            $(document).trigger("reload.metadata", opts.metadata);
            $(document).one("afterReload.metadata", function() {
               $.unblockUI();
            });
         }  
      }).fail(function(xhr) {
          var data = $.parseJSON(xhr.responseText);
          $.unblockUI();
          $.pnotify({
             title: $.i18n("Error importing metadata"),
             text: data.error.message,
             type: 'error'
          });
      });

      return false;
   });

   $(document).on("click", ".metaDataExport", function() {
      var $this = $(this), opts = $this.data();
      //console.log("clicked metadata export", opts);

      $.blockUI({message: "<h2>"+$.i18n("Exporting ...")+"</h2>"});

      $.jsonRpc(foswiki.getScriptUrl("jsonrpc", "MetaDataPlugin", "export"), {
         params: opts
      }).done(function(data) {
          $.unblockUI();
         //console.log("data=",data);
         if (data.result) {
           window.location.href = data.result;
         } else {
           window.location.reload();
         }
      }).fail(function(xhr) {
          var data = $.parseJSON(xhr.responseText);
          $.unblockUI();
          $.pnotify({
             title: $.i18n("Error exporting metadata"),
             text: data.error.message,
             type: 'error'
          });
      });

      return false;
   });

})(jQuery);
