window.config = {
  basePath: window.defaultBasePath ? `/imaging/${window.defaultBasePath}` : '/imaging',
  cypherSearch: false,
  imagingAssistant: false,
  language: 'English_en', // Allowed values 'English_en' ,'Chinese_ch'
  isAdmin: true,
  version: '1__my_versions__',
  edgeBrowser: !(false || !!document.documentMode) && !!window.StyleMedia,
  year: '2020',
  nodeNumber: 3000, // Limit for progressive rendering - For loading large graph faster
  edgeNumber: 9000, // Limit for progressive rendering - For loading large graph faster
  documentationLink: 'https://doc.castsoftware.com/display/IMAGING/CAST+Imaging+System',
  sessionTimeoutAlertBefore: 20, // In Seconds
  investigationCount: 6,
};
