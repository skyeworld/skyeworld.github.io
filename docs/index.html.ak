<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Document</title>
  <meta http-equiv="X-UA-Compatible" content="IE=edge,chrome=1" />
  <meta name="description" content="Description">
  <meta name="viewport" content="width=device-width, user-scalable=no, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0">
  <link rel="stylesheet" href="//unpkg.com/docsify/lib/themes/vue.css">
</head>
<body>
  <div id="app"></div>
  <script>
    window.$docsify = {
      ga: 'UA-55430652-5',
      name: '<span>Doc</span>',
      repo: 'https://github.com/skyeworld',
      loadSidebar: true,
      loadNavbar: true,
      coverpage: false,
      notFoundPage: true,
      subMaxLevel: 4,

      search: 'auto', // default
      
      

      tabs: {
        persist    : true,      // default
        sync       : true,      // default
        theme      : 'classic', // default
        tabComments: true,      // default
        tabHeadings: true       // default
      }
    }
    if (typeof navigator.serviceWorker !== 'undefined') {
    navigator.serviceWorker.register('sw.js')
  }
  </script>
  <script src="//unpkg.com/docsify/lib/docsify.min.js"></script>
  <script src="//cdn.jsdelivr.net/npm/docsify/lib/plugins/search.min.js"></script>
  <script src="//cdn.jsdelivr.net/npm/docsify/lib/plugins/emoji.min.js"></script>
  <script src="//cdn.jsdelivr.net/npm/docsify/lib/plugins/zoom-image.min.js"></script>
  <script src="//cdn.jsdelivr.net/npm/docsify-copy-code"></script>
  <script src="//cdn.jsdelivr.net/npm/docsify-tabs@1"></script>

  <script src="//cdn.jsdelivr.net/npm/prismjs/components/prism-bash.min.js"></script>
  <script src="//cdn.jsdelivr.net/npm/prismjs/components/prism-go.min.js"></script>
  <script src="//cdn.jsdelivr.net/npm/prismjs/components/prism-cpp.min.js"></script>
  <script src="//cdn.jsdelivr.net/npm/prismjs/components/prism-python.min.js"></script>
  <script src="//cdn.jsdelivr.net/npm/prismjs/components/prism-json.min.js"></script>
  <script src="//cdn.jsdelivr.net/npm/prismjs/components/prism-yaml.min.js"></script>
  <script src="//cdn.jsdelivr.net/npm/prismjs/components/prism-protobuf.min.js"></script>
  <script src="//cdn.jsdelivr.net/npm/prismjs/components/prism-sql.min.js"></script>
  <script src="//cdn.jsdelivr.net/npm/docsify/lib/plugins/ga.min.js"></script>

  <!-- PDFObject.js is a required dependency of this plugin -->
  <script src="//cdnjs.cloudflare.com/ajax/libs/pdfobject/2.1.1/pdfobject.min.js"></script> 
  <!-- This is the source code of the pdf embed plugin -->
  <script src="path-to-file/docsify-pdf-embed.js"></script>
  <!-- or use this if you are not hosting the file yourself -->
  <script src="//unpkg.com/docsify-pdf-embed-plugin/src/docsify-pdf-embed.js"></script>
</body>
</html>
