/**
 * 管理端内容管理（演进项已落地）：首页轮播 Banner 与平台公告
 */
import { promptCompat as promptAction, routerCompat as router } from '../common/UiNavigation'
import { COLORS, COLORS_PRIMARY_HEX, SPACING, FONT_SIZE, BORDER_RADIUS, MODULE_COLOR, MODULE_BG, accentBg, accentFg, accentIndexFromText } from '../common/Constants'
import { Banner, Announcement } from '../model/Models'
import {
  syncAdminBannersRemote, updateBannerStatusRemote, deleteBannerRemote, createBannerRemote,
  syncAdminAnnouncementsRemote, updateAnnouncementStatusRemote, deleteAnnouncementRemote, createAnnouncementRemote
} from '../service/AppStorageManager'
import { StatusBadge } from '../components/StatusBadge'
import { logInfo } from '../service/AppLogger'

@Entry
@Component
export struct AdminContentPage {
  @State banners: Banner[] = []
  @State announcements: Announcement[] = []
  @State loading: boolean = false
  @State showBannerDialog: boolean = false
  @State bannerTitle: string = ''
  @State bannerColor: string = COLORS_PRIMARY_HEX
  @State showAnnouncementDialog: boolean = false
  @State announcementTitle: string = ''
  @State announcementContent: string = ''

  async aboutToAppear(): Promise<void> {
    logInfo('Page', '进入管理端内容管理 AdminContentPage')
    await this.loadAll()
  }

  private async loadAll(): Promise<void> {
    this.loading = true
    this.banners = await syncAdminBannersRemote()
    this.announcements = await syncAdminAnnouncementsRemote()
    this.loading = false
  }

  private async toggleBanner(banner: Banner): Promise<void> {
    const target: number = banner.status === 1 ? 0 : 1
    if (await updateBannerStatusRemote(banner.id, target)) {
      await this.loadAll()
    }
  }

  private async deleteBanner(banner: Banner): Promise<void> {
    if (await deleteBannerRemote(banner.id)) {
      promptAction.showToast({ message: 'Banner 已删除', duration: 1500 })
      await this.loadAll()
    }
  }

  private async submitBanner(): Promise<void> {
    if (this.bannerTitle.trim() === '') {
      promptAction.showToast({ message: '请输入 Banner 标题', duration: 1500 })
      return
    }
    const ok: boolean = await createBannerRemote(this.bannerTitle.trim(), '', '', this.bannerColor, 'NONE', '', 0)
    if (ok) {
      this.showBannerDialog = false
      this.bannerTitle = ''
      promptAction.showToast({ message: 'Banner 已新增', duration: 1500 })
      await this.loadAll()
    } else {
      promptAction.showToast({ message: '新增失败，请重试', duration: 2000 })
    }
  }

  private async toggleAnnouncement(a: Announcement): Promise<void> {
    const target: number = a.status === 1 ? 0 : 1
    if (await updateAnnouncementStatusRemote(a.id, target)) {
      await this.loadAll()
    }
  }

  private async deleteAnnouncement(a: Announcement): Promise<void> {
    if (await deleteAnnouncementRemote(a.id)) {
      promptAction.showToast({ message: '公告已删除', duration: 1500 })
      await this.loadAll()
    }
  }

  private async submitAnnouncement(): Promise<void> {
    if (this.announcementTitle.trim() === '' || this.announcementContent.trim() === '') {
      promptAction.showToast({ message: '请填写公告标题和内容', duration: 1500 })
      return
    }
    const ok: boolean = await createAnnouncementRemote(this.announcementTitle.trim(), this.announcementContent.trim())
    if (ok) {
      this.showAnnouncementDialog = false
      this.announcementTitle = ''
      this.announcementContent = ''
      promptAction.showToast({ message: '公告已发布', duration: 1500 })
      await this.loadAll()
    } else {
      promptAction.showToast({ message: '发布失败，请重试', duration: 2000 })
    }
  }

  build() {
    Stack() {
      Column() {
        Row() {
          Text('‹ 返回')
            .fontSize(FONT_SIZE.MD).fontColor(MODULE_COLOR.ADMIN)
            .onClick(() => { router.back() })
          Text('内容管理')
            .fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(MODULE_COLOR.ADMIN)
            .layoutWeight(1).textAlign(TextAlign.Center)
          Text('刷新')
            .fontSize(FONT_SIZE.MD).fontColor(MODULE_COLOR.ADMIN)
            .onClick(() => { this.loadAll() })
        }
        .width('100%').height(56).padding({ left: SPACING.LG, right: SPACING.LG })
        .backgroundColor(MODULE_BG.ADMIN)

        if (this.loading) {
          Column() {
            Text('正在加载…').fontSize(FONT_SIZE.MD).fontColor(COLORS.TEXT_HINT)
          }.layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        } else {
          // 用 List 承载：Scroll 在内容不足一屏时会把内容垂直居中，导致第一条数据不在顶部
          List({ space: SPACING.SM }) {
            // Banner 区
            ListItem() {
              Row({ space: SPACING.SM }) {
                Text('🖼️')
                  .width(28).height(28).textAlign(TextAlign.Center)
                  .backgroundColor(accentBg(0)).borderRadius(BORDER_RADIUS.SM)
                Text('轮播 Banner').fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(MODULE_COLOR.ADMIN).layoutWeight(1)
                Button('新增 Banner').height(32).fontSize(FONT_SIZE.SM)
                  .fontColor(COLORS.TEXT_WHITE).backgroundColor(MODULE_COLOR.ADMIN)
                  .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                  .onClick(() => { this.showBannerDialog = true })
              }.width('100%')
            }
            if (this.banners.length === 0) {
              ListItem() {
                Text('暂无 Banner').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT).width('100%')
              }
            } else {
              ForEach(this.banners, (banner: Banner) => {
                ListItem() {
                  this.BannerCard(banner)
                }
              }, (banner: Banner) => banner.id.toString())
            }

            // 公告区
            ListItem() {
              Row({ space: SPACING.SM }) {
                Text('📢')
                  .width(28).height(28).textAlign(TextAlign.Center)
                  .backgroundColor(accentBg(1)).borderRadius(BORDER_RADIUS.SM)
                Text('平台公告').fontSize(FONT_SIZE.LG).fontWeight(FontWeight.Bold).fontColor(MODULE_COLOR.ADMIN).layoutWeight(1)
                Button('发布公告').height(32).fontSize(FONT_SIZE.SM)
                  .fontColor(COLORS.TEXT_WHITE).backgroundColor(MODULE_COLOR.ADMIN)
                  .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
                  .onClick(() => { this.showAnnouncementDialog = true })
              }.width('100%')
            }
            if (this.announcements.length === 0) {
              ListItem() {
                Text('暂无公告').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_HINT).width('100%')
              }
            } else {
              ForEach(this.announcements, (a: Announcement) => {
                ListItem() {
                  this.AnnouncementCard(a)
                }
              }, (a: Announcement) => a.id.toString())
            }
          }
          .width('100%').layoutWeight(1).scrollBar(BarState.Off)
          .padding({ left: SPACING.LG, right: SPACING.LG, top: SPACING.SM, bottom: SPACING.XXL })
        }
      }
      .width('100%').height('100%').backgroundColor(COLORS.BG_PRIMARY)

      if (this.showBannerDialog) {
        this.BannerDialog()
      }
      if (this.showAnnouncementDialog) {
        this.AnnouncementDialog()
      }
    }
    .width('100%').height('100%')
  }

  @Builder
  BannerCard(banner: Banner) {
    Row({ space: SPACING.SM }) {
      Text(banner.title.substring(0, 1))
        .width(36).height(36).textAlign(TextAlign.Center)
        .fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold)
        .fontColor(accentFg(accentIndexFromText(banner.title)))
        .backgroundColor(accentBg(accentIndexFromText(banner.title)))
        .borderRadius(BORDER_RADIUS.ROUND)
      Column({ space: SPACING.XS }) {
        Text(banner.title).fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
        Text(banner.color).fontSize(FONT_SIZE.XS).fontColor(COLORS.TEXT_HINT)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      StatusBadge({ text: banner.status === 1 ? '展示中' : '已隐藏', mode: banner.status === 1 ? 'success' : 'gray' })
      Button(banner.status === 1 ? '隐藏' : '展示').height(28).fontSize(FONT_SIZE.XS)
        .fontColor(MODULE_COLOR.ADMIN).backgroundColor(MODULE_BG.ADMIN)
        .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
        .onClick(() => { this.toggleBanner(banner) })
      Button('删除').height(28).fontSize(FONT_SIZE.XS)
        .fontColor(COLORS.ERROR).backgroundColor(COLORS.ERROR_LIGHT)
        .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
        .onClick(() => { this.deleteBanner(banner) })
    }
    .width('100%').padding(SPACING.MD).backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.LG)
  }

  @Builder
  AnnouncementCard(a: Announcement) {
    Column({ space: SPACING.XS }) {
      Row({ space: SPACING.SM }) {
        Text(a.title.substring(0, 1))
          .width(32).height(32).textAlign(TextAlign.Center)
          .fontSize(FONT_SIZE.SM).fontWeight(FontWeight.Bold)
          .fontColor(accentFg(accentIndexFromText(a.title)))
          .backgroundColor(accentBg(accentIndexFromText(a.title)))
          .borderRadius(BORDER_RADIUS.MD)
        Text(a.title).fontSize(FONT_SIZE.MD).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY).layoutWeight(1)
        StatusBadge({ text: a.status === 1 ? '已发布' : '已下线', mode: a.status === 1 ? 'success' : 'gray' })
      }.width('100%')
      Text(a.content).fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY).width('100%').maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Row() {
        Blank()
        Button(a.status === 1 ? '下线' : '发布').height(28).fontSize(FONT_SIZE.XS)
          .fontColor(MODULE_COLOR.ADMIN).backgroundColor(MODULE_BG.ADMIN)
          .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
          .onClick(() => { this.toggleAnnouncement(a) })
        Button('删除').height(28).fontSize(FONT_SIZE.XS)
          .fontColor(COLORS.ERROR).backgroundColor(COLORS.ERROR_LIGHT)
          .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
          .margin({ left: SPACING.SM })
          .onClick(() => { this.deleteAnnouncement(a) })
      }.width('100%')
    }
    .width('100%').padding(SPACING.LG).backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.LG)
  }

  @Builder
  BannerDialog() {
    Column() {
      Column({ space: SPACING.MD }) {
        Text('新增 Banner').fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY).width('100%').textAlign(TextAlign.Center)
        Text('标题（必填）').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY).width('100%')
        TextInput({ placeholder: '请输入 Banner 标题，如：新人专享 满20减15', text: this.bannerTitle })
          .width('100%').height(44).fontSize(FONT_SIZE.MD).backgroundColor(COLORS.BG_PRIMARY)
          .borderRadius(BORDER_RADIUS.MD)
          .onChange((v: string) => { this.bannerTitle = v })
        Text('背景色（选填，默认品牌橙）').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY).width('100%')
        TextInput({ placeholder: '#FF6B35', text: this.bannerColor })
          .width('100%').height(44).fontSize(FONT_SIZE.MD).backgroundColor(COLORS.BG_PRIMARY)
          .borderRadius(BORDER_RADIUS.MD)
          .onChange((v: string) => { this.bannerColor = v })
        Row({ space: SPACING.MD }) {
          Button('取消').layoutWeight(1).height(42)
            .fontColor(COLORS.TEXT_SECONDARY).backgroundColor(COLORS.BG_PRIMARY)
            .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
            .onClick(() => { this.showBannerDialog = false })
          Button('新增').layoutWeight(1).height(42)
            .fontColor(COLORS.TEXT_WHITE).backgroundColor(MODULE_COLOR.ADMIN)
            .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
            .onClick(() => { this.submitBanner() })
        }.width('100%')
      }
      .width('86%').padding(SPACING.XL).backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.LG)
    }
    .width('100%').height('100%').backgroundColor(COLORS.OVERLAY)
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
  }

  @Builder
  AnnouncementDialog() {
    Column() {
      Column({ space: SPACING.MD }) {
        Text('发布公告').fontSize(FONT_SIZE.XL).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY).width('100%').textAlign(TextAlign.Center)
        Text('标题（必填）').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY).width('100%')
        TextInput({ placeholder: '请输入公告标题', text: this.announcementTitle })
          .width('100%').height(44).fontSize(FONT_SIZE.MD).backgroundColor(COLORS.BG_PRIMARY)
          .borderRadius(BORDER_RADIUS.MD)
          .onChange((v: string) => { this.announcementTitle = v })
        Text('内容（必填）').fontSize(FONT_SIZE.SM).fontColor(COLORS.TEXT_SECONDARY).width('100%')
        TextArea({ placeholder: '请输入公告内容，最多200字', text: this.announcementContent })
          .width('100%').height(100).maxLength(200).fontSize(FONT_SIZE.MD).backgroundColor(COLORS.BG_PRIMARY)
          .borderRadius(BORDER_RADIUS.MD)
          .onChange((v: string) => { this.announcementContent = v })
        Row({ space: SPACING.MD }) {
          Button('取消').layoutWeight(1).height(42)
            .fontColor(COLORS.TEXT_SECONDARY).backgroundColor(COLORS.BG_PRIMARY)
            .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
            .onClick(() => { this.showAnnouncementDialog = false })
          Button('发布').layoutWeight(1).height(42)
            .fontColor(COLORS.TEXT_WHITE).backgroundColor(MODULE_COLOR.ADMIN)
            .borderRadius(BORDER_RADIUS.ROUND).type(ButtonType.Capsule)
            .onClick(() => { this.submitAnnouncement() })
        }.width('100%')
      }
      .width('86%').padding(SPACING.XL).backgroundColor(COLORS.BG_WHITE).borderRadius(BORDER_RADIUS.LG)
    }
    .width('100%').height('100%').backgroundColor(COLORS.OVERLAY)
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
  }
}
