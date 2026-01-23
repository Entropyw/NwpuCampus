import web_webview from '@ohos.web.webview';
import common from '@ohos.app.ability.common';

@Entry
@Component
struct Index {
  private webController: web_webview.WebviewController = new web_webview.WebviewController();
  private hasInjectedOsm: boolean = false;
  private utf8ArrayToStr(array: Uint8Array): string {
    let out = '';
    let i = 0;
    while (i < array.length) {
      const c = array[i++];
      if (c < 0x80) {
        out += String.fromCharCode(c);
      } else if (c >= 0xC0 && c < 0xE0) {
        const c2 = array[i++];
        out += String.fromCharCode(((c & 0x1F) << 6) | (c2 & 0x3F));
      } else if (c >= 0xE0 && c < 0xF0) {
        const c2 = array[i++];
        const c3 = array[i++];
        out += String.fromCharCode(((c & 0x0F) << 12) | ((c2 & 0x3F) << 6) | (c3 & 0x3F));
      } else {
        const c2 = array[i++];
        const c3 = array[i++];
        const c4 = array[i++];
        let codepoint = ((c & 0x07) << 18) | ((c2 & 0x3F) << 12) | ((c3 & 0x3F) << 6) | (c4 & 0x3F);
        codepoint -= 0x10000;
        out += String.fromCharCode((codepoint >> 10) + 0xD800);
        out += String.fromCharCode((codepoint & 0x3FF) + 0xDC00);
      }
    }
    return out;
  }

  private async injectOsmToWeb(): Promise<void> {
    if (this.hasInjectedOsm) {
      return;
    }
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const rawContent = await context.resourceManager.getRawFileContent('map.osm');
      const uint8 = rawContent instanceof Uint8Array ? rawContent : new Uint8Array(rawContent);
      // Proper UTF-8 decode to handle multibyte characters (Chinese, etc.).
      const osmText = this.utf8ArrayToStr(uint8);
      const payload = JSON.stringify(osmText);
      const jsCode = `window.__PENDING_OSM_TEXT=${payload};` +
        `if (window.setOSMText) { window.setOSMText(window.__PENDING_OSM_TEXT); }`;
      await this.webController.runJavaScript(jsCode);
      this.hasInjectedOsm = true;
      console.info('OSM 注入成功');
    } catch (error) {
      console.error(`OSM 注入失败: ${String(error)}`);
    }
  }

  build() {
    Stack() {
      Web({
        src: 'resource://rawfile/custom_map.html',
        controller: this.webController
      })
        .onPageEnd(() => {
          this.injectOsmToWeb();
        })
        .width('100%')
        .height('100%');

      Row() {
        Text('本地 OSM 地图 · 支持双指缩放与拖动')
          .fontSize(14)
          .fontColor(Color.White)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor('rgba(0, 0, 0, 0.55)')
          .borderRadius(16);
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ top: 18 });
    }
    .width('100%')
    .height('100%');
  }
}