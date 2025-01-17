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
