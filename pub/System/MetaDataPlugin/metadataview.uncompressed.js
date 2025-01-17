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
