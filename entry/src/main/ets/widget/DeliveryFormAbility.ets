import { FormExtensionAbility, formBindingData, formProvider } from '@kit.FormKit'

export default class DeliveryFormAbility extends FormExtensionAbility {
  onAddForm(): formBindingData.FormBindingData {
    return formBindingData.createFormBindingData({ statusText: '打开应用同步订单', syncedText: '暂无订单快照' })
  }

  onUpdateForm(formId: string): void {
    // No persisted account data in the extension; restart fails closed.
    formProvider.updateForm(formId, this.onAddForm()).catch(() => {})
  }

  onFormEvent(formId: string, message: string): void {
    try {
      const event: Record<string, string> = JSON.parse(message) as Record<string, string>
      if (event['message'] === 'rider') { this.animateRider(formId) }
    } catch (_) {}
  }

  private async animateRider(formId: string): Promise<void> {
    try {
      const rect = await formProvider.getFormRect(formId)
      if (rect.width <= 0 || rect.height <= 0) { return }
      await formProvider.requestOverflow(formId, {
        area: { left: 0, top: 0, width: rect.width, height: rect.height }, duration: 3000
      })
    } catch (_) { /* Unsupported launchers retain the ordinary card and order button. */ }
  }
}
