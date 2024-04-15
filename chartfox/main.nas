include('baseApp.nas');
include('eventSource.nas');
include('gui/button.nas');
include('/html/main.nas');

var AUTH_NONE = 0; # No authentication started yet
var AUTH_OK = 1; # Successfully authenticated
var AUTH_CODE = 2; # Fetching authentication code
var AUTH_TOKEN = 3; # Fetching bearer token
var AUTH_ERROR = 4; # Authentication error

var ChartfoxApp = {
    new: func(masterGroup) {
        var m = BaseApp.new(masterGroup);
        m.parents = [me] ~ m.parents;
        m.contentGroup = nil;
        m.currentListing = nil;
        m.currentPage = 0;
        m.numPages = nil;
        m.currentPath = "";
        m.currentTitle = "Chartfox";
        m.currentPageURL = nil;
        m.currentPageMetaURL = nil;
        m.history = [];
        m.zoomLevel = 0;
        m.img = nil;
        m.zoomScroll = nil;
        m.favorites = [];
        m.xhr = nil;
        m.rotation = 0;
        m.companionURL = 'http://localhost:7675/';
        m.chartfoxURL = 'https://api.chartfox.org/';
        m.clientID = '9b3db983-1ebb-4464-af4e-68ae582dd3fd';
        m.authCodeProp = props.globals.getNode('/chartfox/oauth/code', 1);
        m.authAccessTokenProp = props.globals.getNode('/chartfox/oauth/access-token', 1);
        m.authRefreshTokenProp = props.globals.getNode('/chartfox/oauth/refresh-token', 1);
        m.authStateProp = props.globals.getNode('/chartfox/oauth/state', 1);
        m.authStateProp.setIntValue(AUTH_NONE);
        m.authCodeProp.setValue('');
        m.authAccessTokenProp.setValue('');
        m.authRefreshTokenProp.setValue('');
        return m;
    },

    generateCodeVerifier: func (onSuccess, onFailure) {
        var self = me;
        debug.dump("generateCodeVerifier");
        var filename = getprop('/sim/fg-home') ~ "/Export/chartfoxOAuthVerifier.xml";
        debug.dump('FILENAME', filename);
        var handleSuccess = func (r) {
            var topNode = io.readxml(filename);
            if (topNode == nil) {
                logprint(4, "Chartfox: Invalid verifier response: malformed XML");
                self.showErrorScreen(
                    [ "Invalid verifier response:"
                    , "Malformed XML"
                    ]);
            }
            else {
                var resultNode = topNode.getNode("result");
                var challenge = resultNode.getChild("challenge").getValue();
                var verifier = resultNode.getChild("verifier").getValue();
                logprint(2, "Challenge response", challenge, verifier);
                onSuccess(challenge, verifier);
            }
        }
        var url = me.companionURL ~ 'chartfox/oauth/challenge';
        debug.dump('URL', url);
        http.save(url, filename)
            .done(func (r) {
                    var errs = [];
                    call(handleSuccess, [r], nil, {}, errs);
                    debug.dump(errs);
                    if (size(errs) > 0) {
                        debug.printerror(errs);
                        self.showErrorScreen(errs);
                    }
                    else {
                        handleSuccess(r);
                    }
                })
            .fail(onFailure)
            .always(func { });
    },

    logout: func () {
        me.authStateProp.setIntValue(AUTH_NONE);
        me.authCodeProp.setValue('');
        me.authAccessTokenProp.setValue('');
        me.authRefreshTokenProp.setValue('');
        me.showHome();
    },

    authorize: func () {
        var self = me;
        me.generateCodeVerifier(func (challenge, verifier) {
            var authRequestURL = me.chartfoxURL ~
                                    'oauth/authorize?client_id=' ~ urlencode(me.clientID) ~
                                        '&response_type=code' ~
                                        '&code_challenge=' ~ urlencode(challenge) ~
                                        '&code_challenge_method=S256' ~
                                        '&scope=airports:view+charts:index+charts:view' ~
                                        '&state=asdf1234' ~
                                        '&redirect_uri=' ~ urlencode("http://localhost:10000/aircraft-dir/WebPanel/chartfox_oauth.html") ~
                                        '';
            debug.dump('URL', authRequestURL);
            var listener = setlistener(me.authCodeProp, func (val) {
                debug.dump("AUTH RESPONSE", val);
                me.authStateProp.setIntValue(AUTH_TOKEN);
                me.showHome();
                if (listener != nil)
                    removelistener(listener);
                me.fetchToken(verifier);
            }, 0, 1);
            me.authStateProp.setIntValue(AUTH_CODE);
            me.showHome();
            fgcommand('open-browser', props.Node.new({ "url": authRequestURL }));
        },
        func(r) {
            debug.dump("FAILURE", r.status, r.reason);
            self.authStateProp.setIntValue(AUTH_ERROR);
            self.showErrorScreen(
                [ "Authentication failure:"
                , r.reason
                , "See fgfs.log for details."
                ]);
        });
    },

    fetchToken: func (verifier) {
        var self = me;
        var state = me.authStateProp.getValue();
        if (state != AUTH_TOKEN) {
            logprint(4, "Incorrect state for fetching token");
        }
        var code = me.authCodeProp.getValue();
        var filename = getprop('/sim/fg-home') ~ "/Export/chartfoxOAuthTokens.xml";
        var onSuccess = func(r) {
            var topNode = io.readxml(filename);
            if (topNode == nil) {
                self.authStateProp.setIntValue(AUTH_ERROR);
                self.showErrorScreen(
                    [ "Invalid token response:"
                    , "Malformed XML"
                    ]);
            }
            else {
                var resultNode = topNode.getNode("tokens");
                if (resultNode == nil) {
                    self.authStateProp.setIntValue(AUTH_ERROR);
                    var errorNode = topNode.getChild("error");
                    if (errorNode != nil) {
                        self.showErrorScreen(
                            [ "ChartFox error"
                            , errorNode.getValue()
                            ]
                        );
                    }
                    else {
                        self.showErrorScreen(
                            [ "ChartFox error"
                            , "Invalid response"
                            ]
                        );
                    }
                }
                else {
                    var access = resultNode.getChild("access").getValue();
                    var refresh = resultNode.getChild("refresh").getValue();
                    self.authAccessTokenProp.setValue(access);
                    self.authRefreshTokenProp.setValue(refresh);
                    self.authStateProp.setIntValue(AUTH_OK);
                    self.showHome();
                }
            }
        };
        var onFailure = func(r) {
            debug.dump("FAILURE", r.status, r.reason);
            self.authStateProp.setIntValue(AUTH_ERROR);
            self.showErrorScreen(
                [ "Authentication failure:"
                , r.reason
                , "See fgfs.log for details."
                ]);
        };

        var tokenURL = me.companionURL ~ 'chartfox/oauth/token?code=' ~ urlencode(code) ~
                                            '&client_id=' ~ urlencode(me.clientID) ~
                                            '&code_verifier=' ~ urlencode(verifier);
        debug.dump(tokenURL);
        var xhr = http.save(tokenURL, filename)
            .done(func (r) {
                    var errs = [];
                    call(onSuccess, [r], nil, {}, errs);
                    if (size(errs) > 0) {
                        debug.printerror(errs);
                        self.showErrorScreen(errs);
                    }
                    else {
                    }
                })
            .fail(onFailure)
            .always(func { });
    },

    handleBack: func () {
        var popped = pop(me.history);
        if (popped != nil) {
            if (popped[0] == "*FAVS*")
                me.loadFavorites(popped[2], 0);
            else
                me.loadListing(popped[0], popped[1], popped[2], 0);
        }
    },

    initialize: func () {
        me.stylesheet = html.CSS.loadStylesheet(me.assetDir ~ 'style.css');
        me.companionURL = getprop('/instrumentation/efb/flightbag-companion-uri') or 'http://localhost:7675/';
        me.bgfill = me.masterGroup.createChild('path')
                        .rect(0, 0, 512, 768)
                        .setColorFill(128, 128, 128);
        # me.bglogo = me.masterGroup.createChild('image')
        #                 .set('src', me.assetDir ~ 'background.png')
        #                 .setTranslation(256 - 128, 384 - 128);
        me.bgfog = me.masterGroup.createChild('path')
                        .rect(0, 0, 512, 768)
                        .setColorFill(255, 255, 255, 0.8);
        me.contentGroup = me.masterGroup.createChild('group');

        me.showHome();
    },

    clear: func {
        me.rootWidget.removeAllChildren();
        me.zoomScroll = nil;
        me.zoomLevel = 0;
        me.sx = 0.0;
        me.sy = 0.0;
        me.img = nil;
        me.contentGroup.removeAllChildren();
    },

    showErrorScreen: func (errs) {
        var self = me;

        me.clear();

        var renderContext =
                html.makeDefaultRenderContext(
                    me.contentGroup,
                    font_mapper,
                    0, 64, 512, 704);
        var errorItems = [];
        foreach (var err; errs) {
            if (typeof(err) == 'scalar') {
                err = err ~ ''; # Make sure it's really a string
                if (substr(err, 0, 7) == 'http://' or
                    substr(err, 0, 8) == 'https://') {
                    append(errorItems, H.p(H.a({'href': err}, err)));
                }
                else {
                    append(errorItems, H.p(err));
                }
            }
            elsif (isa(err, html.DOM.Node)) {
                append(errorItems, err);
            }
            else {
                debug.dump(err);
            }
        }
        var doc = H.html(
                    H.body({class: 'error'},
                        H.h1('Error'),
                        H.div({class: 'error-details'},
                            errorItems)));
        me.stylesheet.apply(doc);
        html.showDOM(doc, renderContext);
        var okButton = Button.new(
                            me.contentGroup,
                            "OK",
                            128, 500, 256);
        okButton.setHandler(func {
            me.showHome();
        });
    },

    showBaseScreen: func () {
        me.contentGroup.createChild('image')
                .setTranslation(224, 600)
                .set('src', me.basedir ~ '/chartfox.png');
        me.contentGroup.createChild('text')
                .setText('Powered by ChartFox')
                .setTranslation(256, 690)
                .setFont(font_mapper('sans', 'normal'))
                .setFontSize(16)
                .setColor(0,0,0)
                .setAlignment('center-top');
        me.contentGroup.createChild('text')
                .setText('https://chartfox.org/')
                .setTranslation(256, 710)
                .setFont(font_mapper('sans', 'normal'))
                .setFontSize(16)
                .setColor(0,0,1)
                .setAlignment('center-top');
    },

    showLoggedOut: func () {
        var self = me;

        me.contentGroup.removeAllChildren();
        me.rootWidget.removeAllChildren();

        me.showBaseScreen();

        var loginButton = Button.new(
                            me.contentGroup,
                            "Log In",
                            128, 220, 256);
        loginButton.setHandler(func {
            self.authorize();
        });

        me.contentGroup.createChild('text')
                .setText('ChartFox Login')
                .setTranslation(256, 64)
                .setFont(font_mapper('sans', 'bold'))
                .setFontSize(32)
                .setColor(0,0,0)
                .setAlignment('center-top');

        me.contentGroup.createChild('text')
                .setText('You are not currently logged into ChartFox.')
                .setTranslation(256, 125)
                .setFont(font_mapper('sans', 'normal'))
                .setFontSize(16)
                .setColor(0,0,0)
                .setAlignment('center-top');

        me.contentGroup.createChild('text')
                .setText('Clicking the login button below will open a window in your browser.')
                .setTranslation(256, 165)
                .setFont(font_mapper('sans', 'normal'))
                .setFontSize(16)
                .setColor(0,0,0)
                .setAlignment('center-top');


        me.rootWidget.appendChild(loginButton);
    },

    showLoggedIn: func () {
        var self = me;

        me.contentGroup.removeAllChildren();
        me.rootWidget.removeAllChildren();

        me.showBaseScreen();

        me.contentGroup.createChild('text')
                .setText('Logged in')
                .setTranslation(256, 180)
                .setFont(font_mapper('sans', 'bold'))
                .setFontSize(16)
                .setColor(1, 1, 1)
                .setAlignment('center-top');

        var logoutButton = Button.new(
                            me.contentGroup,
                            "Log Out",
                            128, 220, 256);
        logoutButton.setHandler(func {
            self.logout();
        });

        me.contentGroup.createChild('text')
                .setText('ChartFox Login')
                .setTranslation(256, 64)
                .setFont(font_mapper('sans', 'bold'))
                .setFontSize(32)
                .setColor(0,0,0)
                .setAlignment('center-top');

        me.contentGroup.createChild('text')
                .setText('You are currently logged into ChartFox.')
                .setTranslation(256, 125)
                .setFont(font_mapper('sans', 'normal'))
                .setFontSize(16)
                .setColor(0,0,0)
                .setAlignment('center-top');

        me.contentGroup.createChild('text')
                .setText('Use the Charts app to access ChartFox.')
                .setTranslation(256, 165)
                .setFont(font_mapper('sans', 'normal'))
                .setFontSize(16)
                .setColor(0,0,0)
                .setAlignment('center-top');


        me.rootWidget.appendChild(logoutButton);
    },

    showLoginProgress: func (status) {
        var self = me;

        me.contentGroup.removeAllChildren();
        me.rootWidget.removeAllChildren();

        var statusText = status;
        if (status == AUTH_OK) { statusText = "Logged in"; }
        elsif (status == AUTH_ERROR) { statusText = "Authentication error"; }
        elsif (status == AUTH_CODE) { statusText = "Getting login code"; }
        elsif (status == AUTH_TOKEN) { statusText = "Fetching token"; }
        elsif (status == AUTH_NONE) { statusText = "Logged out"; }

        me.contentGroup.createChild('text')
                .setText('Login in progress...')
                .setTranslation(256, 180)
                .setFont(font_mapper('sans', 'bold'))
                .setFontSize(16)
                .setColor(0, 0, 0)
                .setAlignment('center-top');

        me.contentGroup.createChild('text')
                .setText(statusText)
                .setTranslation(256, 220)
                .setFont(font_mapper('sans', 'bold'))
                .setFontSize(16)
                .setColor(0, 0, 0)
                .setAlignment('center-top');
    },



    showHome: func () {
        var status = me.authStateProp.getValue();
        if (status == AUTH_NONE or status == AUTH_ERROR) {
            me.showLoggedOut();
        }
        elsif (status == AUTH_OK) {
            me.showLoggedIn();
        }
        else {
            me.showLoginProgress(status);
        }
    },
};

registerApp('chartfox', 'Chartfox', 'chartfox.png', ChartfoxApp);
