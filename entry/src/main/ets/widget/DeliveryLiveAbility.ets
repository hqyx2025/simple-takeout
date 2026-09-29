import { LiveFormExtensionAbility, LiveFormInfo } from '@kit.FormKit'
import { UIExtensionContentSession } from '@kit.AbilityKit'

export default class DeliveryLiveAbility extends LiveFormExtensionAbility {
  onLiveFormCreate(info: LiveFormInfo, session: UIExtensionContentSession): void {
    const storage: LocalStorage = new LocalStorage()
    storage.setOrCreate('formId', info.formId)
    storage.setOrCreate('formRect', info.rect)
    storage.setOrCreate('radius', info.borderRadius)
    // Synchronous load is required by Live Form. Animation is decorative, not live tracking.
    try {
      session.loadContent('widget/DeliveryLive', storage)
    } catch (_) { /* Keep the ordinary card usable if the session is unavailable. */ }
  }
}
