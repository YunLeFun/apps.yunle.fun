package fun.yunle.apps.wxapi;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.util.Log;

import com.tencent.mm.opensdk.constants.ConstantsAPI;
import com.tencent.mm.opensdk.modelbase.BaseReq;
import com.tencent.mm.opensdk.modelbase.BaseResp;
import com.tencent.mm.opensdk.modelbiz.ChooseCardFromWXCardPackage;
import com.tencent.mm.opensdk.modelbiz.WXLaunchMiniProgram;
import com.tencent.mm.opensdk.modelmsg.SendAuth;
import com.tencent.mm.opensdk.modelmsg.ShowMessageFromWX;
import com.tencent.mm.opensdk.modelmsg.WXMediaMessage;
import com.tencent.mm.opensdk.openapi.IWXAPI;
import com.tencent.mm.opensdk.openapi.IWXAPIEventHandler;

import fun.yunle.apps.MainActivity;

import org.apache.cordova.CallbackContext;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import xu.li.cordova.wechat.Wechat;

/** Callback endpoint required by the WeChat Android OpenSDK package convention. */
public class EntryActivity extends Activity implements IWXAPIEventHandler {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        handleIntent(getIntent());
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        handleIntent(intent);
    }

    private void handleIntent(Intent intent) {
        IWXAPI api = Wechat.getWxAPI(this);
        if (api == null) {
            startMainActivity();
        } else {
            api.handleIntent(intent, this);
        }
    }

    @Override
    public void onResp(BaseResp resp) {
        Log.d(Wechat.TAG, resp.toString());
        CallbackContext context = Wechat.getCurrentCallbackContext();
        if (context == null) {
            startMainActivity();
            return;
        }

        switch (resp.errCode) {
            case BaseResp.ErrCode.ERR_OK:
                handleSuccess(resp, context);
                break;
            case BaseResp.ErrCode.ERR_USER_CANCEL:
                context.error(Wechat.ERROR_WECHAT_RESPONSE_USER_CANCEL);
                break;
            case BaseResp.ErrCode.ERR_AUTH_DENIED:
                context.error(Wechat.ERROR_WECHAT_RESPONSE_AUTH_DENIED);
                break;
            case BaseResp.ErrCode.ERR_SENT_FAILED:
                context.error(Wechat.ERROR_WECHAT_RESPONSE_SENT_FAILED);
                break;
            case BaseResp.ErrCode.ERR_UNSUPPORT:
                context.error(Wechat.ERROR_WECHAT_RESPONSE_UNSUPPORT);
                break;
            case BaseResp.ErrCode.ERR_COMM:
                context.error(Wechat.ERROR_WECHAT_RESPONSE_COMMON);
                break;
            default:
                context.error(Wechat.ERROR_WECHAT_RESPONSE_UNKNOWN);
                break;
        }
        finish();
    }

    private void handleSuccess(BaseResp resp, CallbackContext context) {
        switch (resp.getType()) {
            case ConstantsAPI.COMMAND_SENDAUTH:
                auth((SendAuth.Resp) resp, context);
                break;
            case ConstantsAPI.COMMAND_CHOOSE_CARD_FROM_EX_CARD_PACKAGE:
                invoice((ChooseCardFromWXCardPackage.Resp) resp, context);
                break;
            case ConstantsAPI.COMMAND_LAUNCH_WX_MINIPROGRAM:
                JSONObject miniProgram = new JSONObject();
                try {
                    miniProgram.put("extMsg", ((WXLaunchMiniProgram.Resp) resp).extMsg);
                } catch (JSONException error) {
                    Log.e(Wechat.TAG, error.getMessage());
                }
                context.success(miniProgram);
                break;
            default:
                context.success();
                break;
        }
    }

    private void auth(SendAuth.Resp response, CallbackContext context) {
        JSONObject result = new JSONObject();
        try {
            result.put("code", response.code);
            result.put("state", response.state);
            result.put("country", response.country);
            result.put("lang", response.lang);
        } catch (JSONException error) {
            Log.e(Wechat.TAG, error.getMessage());
        }
        context.success(result);
    }

    private void invoice(ChooseCardFromWXCardPackage.Resp response, CallbackContext context) {
        JSONObject result = new JSONObject();
        try {
            result.put("data", new JSONArray(response.cardItemList));
        } catch (JSONException error) {
            Log.e(Wechat.TAG, error.getMessage());
        }
        context.success(result);
    }

    @Override
    public void onReq(BaseReq req) {
        if (req.getType() == ConstantsAPI.COMMAND_SHOWMESSAGE_FROM_WX
            && req instanceof ShowMessageFromWX.Req) {
            WXMediaMessage message = ((ShowMessageFromWX.Req) req).message;
            startMainActivity();
            Wechat.transmitLaunchFromWX(message.messageExt);
        }
        finish();
    }

    private void startMainActivity() {
        Intent intent = new Intent(getApplicationContext(), MainActivity.class);
        intent.setFlags(
            Intent.FLAG_ACTIVITY_SINGLE_TOP
                | Intent.FLAG_ACTIVITY_NEW_TASK
                | Intent.FLAG_ACTIVITY_CLEAR_TOP
        );
        intent.setPackage(getApplicationContext().getPackageName());
        getApplicationContext().startActivity(intent);
        finish();
    }
}
