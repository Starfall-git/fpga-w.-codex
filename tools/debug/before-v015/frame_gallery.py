"""V0.14 / 68: persistent gallery, image-coordinate annotation and comparison."""
import math
from pathlib import Path
import tkinter as tk
from tkinter import ttk, filedialog, colorchooser, messagebox
from PIL import Image, ImageTk
from .snapshots import ImageDocument


def comparison_columns(sizes, width, height):
    """Choose the grid maximizing visible image area, including mixed aspect ratios."""
    if not sizes: return 1
    def score(cols):
        rows = math.ceil(len(sizes)/cols)
        w, h = max(1, width/cols-16), max(1, height/rows-48)
        return sum((min(w/iw,h/ih)**2)*iw*ih for iw,ih in sizes)
    return max(range(1,len(sizes)+1), key=score)


class Editor:
    def __init__(self, parent, store, path, saved=None):
        self.store, self.path, self.saved = store, Path(path), saved
        self.doc = ImageDocument(store.load(path))
        self.win = tk.Toplevel(parent); self.win.title('冻结帧编辑 · ' + self.path.stem)
        self.win.geometry('1100x800')
        self.tool = tk.StringVar(value='pen'); self.color='#ff4545'
        self.width=tk.IntVar(value=4); self.percent=tk.StringVar(value='100')
        self.scale=1.; self.points=[]; self.start=None; self.rectangle=None
        bar=ttk.Frame(self.win,padding=8);bar.pack(fill='x')
        for label,value in [('画笔批注','pen'),('鼠标框选裁剪','crop')]:
            ttk.Radiobutton(bar,text=label,value=value,variable=self.tool).pack(side='left')
        ttk.Button(bar,text='颜色',command=self.pick_color).pack(side='left')
        ttk.Spinbox(bar,from_=1,to=30,width=3,textvariable=self.width).pack(side='left',padx=5)
        for label,call in [('撤销',self.undo),('上下翻转',lambda:self.flip(False)),('左右镜像',lambda:self.flip(True))]:
            ttk.Button(bar,text=label,command=call).pack(side='left',padx=3)
        bar2=ttk.Frame(self.win,padding=8);bar2.pack(fill='x')
        ttk.Label(bar2,text='修改图片尺寸 %').pack(side='left')
        entry=ttk.Entry(bar2,textvariable=self.percent,width=6);entry.pack(side='left')
        entry.bind('<Return>',lambda _:self.resize())
        ttk.Button(bar2,text='应用缩放',command=self.resize).pack(side='left')
        ttk.Button(bar2,text='查看 −',command=lambda:self.zoom(.8)).pack(side='left',padx=3)
        ttk.Button(bar2,text='查看 +',command=lambda:self.zoom(1.25)).pack(side='left',padx=3)
        ttk.Button(bar2,text='适应窗口',command=self.fit).pack(side='left')
        ttk.Button(bar2,text='另存到仓库',command=self.save).pack(side='right')
        ttk.Button(bar2,text='下载图片',command=self.export).pack(side='right',padx=5)
        self.info=tk.StringVar(value='拖动画笔批注；裁剪模式下拖动框选，松开后裁剪。查看缩放不改变图片尺寸。')
        ttk.Label(self.win,textvariable=self.info).pack(fill='x',padx=8)
        area=ttk.Frame(self.win);area.pack(fill='both',expand=True)
        self.canvas=tk.Canvas(area,bg='#17222d',highlightthickness=0)
        sx=ttk.Scrollbar(area,orient='horizontal',command=self.canvas.xview)
        sy=ttk.Scrollbar(area,command=self.canvas.yview)
        self.canvas.configure(xscrollcommand=sx.set,yscrollcommand=sy.set)
        area.rowconfigure(0,weight=1);area.columnconfigure(0,weight=1)
        self.canvas.grid(row=0,column=0,sticky='nsew');sy.grid(row=0,column=1,sticky='ns');sx.grid(row=1,column=0,sticky='ew')
        self.canvas.bind('<ButtonPress-1>',self.press);self.canvas.bind('<B1-Motion>',self.drag);self.canvas.bind('<ButtonRelease-1>',self.release)
        self.win.after(80,self.fit)

    def render(self):
        w,h=self.doc.image.size
        size=(max(1,round(w*self.scale)),max(1,round(h*self.scale)))
        self.photo=ImageTk.PhotoImage(self.doc.image.resize(size,Image.Resampling.LANCZOS),master=self.win)
        self.canvas.delete('all');self.canvas.create_image(0,0,image=self.photo,anchor='nw')
        self.canvas.configure(scrollregion=(0,0,*size));self.rectangle=None

    def fit(self):
        self.scale=min(max(1,self.canvas.winfo_width())/self.doc.image.width,max(1,self.canvas.winfo_height())/self.doc.image.height,1)
        self.render()

    def zoom(self,factor):
        self.scale=max(.05,min(4,self.scale*factor,(8_000_000/(self.doc.image.width*self.doc.image.height))**.5));self.render()

    def point(self,event):
        # Crop coordinates denote pixel boundaries; permit the full right/bottom edge.
        margin = 0 if self.tool.get() == 'crop' else 1
        return (max(0,min(self.doc.image.width-margin,self.canvas.canvasx(event.x)/self.scale)),
                max(0,min(self.doc.image.height-margin,self.canvas.canvasy(event.y)/self.scale)))

    def press(self,event):
        self.start=self.point(event);self.points=[self.start]
        if self.tool.get()=='pen':
            try: self.pen_width=max(1,min(30,self.width.get()))
            except (ValueError,tk.TclError): self.pen_width=4
            self.doc.checkpoint()

    def drag(self,event):
        if self.start is None:return
        p=self.point(event)
        if self.tool.get()=='pen':
            last=self.points[-1];self.points.append(p)
            self.canvas.create_line(last[0]*self.scale,last[1]*self.scale,p[0]*self.scale,p[1]*self.scale,
                                    fill=self.color,width=max(1,self.pen_width*self.scale),capstyle='round')
        else:
            if self.rectangle:self.canvas.delete(self.rectangle)
            self.rectangle=self.canvas.create_rectangle(*(v*self.scale for v in (*self.start,*p)),outline='#44dcff',width=2)

    def release(self,event):
        if self.start is None:return
        p=self.point(event)
        try:
            if self.tool.get()=='pen':self.doc.stroke([*self.points,p],self.color,self.pen_width)
            else:self.doc.crop((*self.start,*p))
            self.render()
        except ValueError as e:self.info.set(str(e))
        self.start=None

    def pick_color(self):
        result=colorchooser.askcolor(self.color,parent=self.win)[1]
        if result:self.color=result

    def undo(self):self.doc.undo();self.render()
    def flip(self,horizontal):self.doc.flip(horizontal);self.render()
    def resize(self):
        try:self.doc.resize(self.percent.get());self.fit()
        except ValueError as e:self.info.set(str(e))

    def save(self):
        try:
            path=self.store.save(self.doc.image,parent=self.path.name)
            self.info.set('已另存到仓库：'+path.name)
            if self.saved:self.saved()
        except OSError as e:messagebox.showerror('保存失败',str(e),parent=self.win)

    def export(self):
        path=filedialog.asksaveasfilename(parent=self.win,initialfile=self.path.stem+'-edited.png',defaultextension='.png',filetypes=[('PNG','*.png'),('JPEG','*.jpg')])
        if path:
            try:self.doc.image.save(path)
            except OSError as e:messagebox.showerror('下载失败',str(e),parent=self.win)


class Comparison:
    def __init__(self,parent,store,paths,saved):
        self.store,self.paths,self.saved=store,paths,saved
        self.win=tk.Toplevel(parent);self.win.title(f'冻结帧对比 · {len(paths)} 张');self.win.geometry('1250x800')
        ttk.Label(self.win,text='每张图片可独立打开批注；保存后生成仓库新副本，原图保留。',padding=8).pack(fill='x')
        self.area=ttk.Frame(self.win);self.area.pack(fill='both',expand=True)
        # Keep only bounded previews in the comparison; editor loads original.
        self.images=[]
        for p in paths:
            im=store.load(p);im.thumbnail((1280,720));self.images.append(im)
        self.timer=None;self.previous=(0,0);self.photos=[];self.cells=[]
        self.area.bind('<Configure>',self.configure)
        self.win.bind('<Destroy>',self.destroyed)

    def destroyed(self,event):
        if event.widget==self.win and self.timer:
            self.win.after_cancel(self.timer);self.timer=None

    def configure(self,event):
        if (event.width,event.height)==self.previous:return
        self.previous=(event.width,event.height)
        if self.timer:self.win.after_cancel(self.timer)
        self.timer=self.win.after(100,self.render)

    def render(self):
        self.timer=None
        for c in self.cells:c.destroy()
        self.cells=[];self.photos=[]
        w,h=self.previous;cols=comparison_columns([im.size for im in self.images],w,h);rows=math.ceil(len(self.images)/cols)
        for index,(im,path) in enumerate(zip(self.images,self.paths)):
            cell=ttk.Frame(self.area,padding=4);cell.place(relx=(index%cols)/cols,rely=(index//cols)/rows,relwidth=1/cols,relheight=1/rows)
            preview=im.copy();preview.thumbnail((max(1,int(w/cols)-12),max(1,int(h/rows)-44)))
            photo=ImageTk.PhotoImage(preview,master=self.win);self.photos.append(photo)
            ttk.Button(cell,text=f'{index+1} · 打开 / 批注',command=lambda p=path:Editor(self.win,self.store,p,self.saved)).pack()
            label=ttk.Label(cell,image=photo);label.pack(expand=True)
            label.bind('<Double-1>',lambda _,p=path:Editor(self.win,self.store,p,self.saved));self.cells.append(cell)


class Gallery:
    def __init__(self,parent,store):
        self.store=store;self.win=tk.Toplevel(parent);self.win.title('冻结帧仓库');self.win.geometry('1050x750')
        bar=ttk.Frame(self.win,padding=10);bar.pack(fill='x')
        ttk.Button(bar,text='刷新',command=self.refresh).pack(side='left')
        ttk.Button(bar,text='对比所选',command=self.compare).pack(side='left',padx=8)
        ttk.Label(bar,text='勾选多张进行对比；点击缩略图打开编辑').pack(side='left')
        self.status=tk.StringVar();ttk.Label(self.win,textvariable=self.status,padding=8).pack(fill='x')
        self.canvas=tk.Canvas(self.win,highlightthickness=0)
        scroll=ttk.Scrollbar(self.win,command=self.canvas.yview);scroll.pack(side='right',fill='y')
        self.canvas.configure(yscrollcommand=scroll.set);self.canvas.pack(fill='both',expand=True)
        self.inner=ttk.Frame(self.canvas);self.canvas.create_window(0,0,window=self.inner,anchor='nw')
        self.inner.bind('<Configure>',lambda _:self.canvas.configure(scrollregion=self.canvas.bbox('all')))
        self.photos=[];self.selected={};self.refresh()

    def refresh(self):
        selected={p for p,v in self.selected.items() if v.get()}
        for c in self.inner.winfo_children():c.destroy()
        self.photos=[];self.selected={};entries=self.store.entries()
        self.status.set(f'{len(entries)} 张 · {self.store.root}')
        for index,path in enumerate(entries):
            try:im=self.store.load(path);im.thumbnail((230,135))
            except (OSError,ValueError):continue
            cell=ttk.Frame(self.inner,padding=8);cell.grid(row=index//4,column=index%4,sticky='nsew')
            photo=ImageTk.PhotoImage(im,master=self.win);self.photos.append(photo)
            ttk.Button(cell,image=photo,command=lambda p=path:Editor(self.win,self.store,p,self.refresh)).pack()
            v=tk.BooleanVar(value=path in selected);self.selected[path]=v
            ttk.Checkbutton(cell,text=path.stem[:22],variable=v).pack(anchor='w')

    def compare(self):
        paths=[p for p,v in self.selected.items() if v.get()]
        if len(paths)<2:messagebox.showinfo('选择图片','请至少选择两张冻结帧',parent=self.win);return
        Comparison(self.win,self.store,paths,self.refresh)
