function axesPlaceholder(app, ax, message)
% まだ描いていない図の枠：目盛りだけの空の枠を出さず、中央に案内の文字（何を押すとここに出るか）を出す。
% 図を描く関数は cla(ax, 'reset') と ax.Visible = 'on' で元に戻す
for k = 1:numel(ax)
    cla(ax(k), 'reset');
    legend(ax(k), 'off');
    colorbar(ax(k), 'off');
    ax(k).Visible = 'off';
    if k == 1
        text(ax(k), 0.5, 0.5, message, 'Units', 'normalized', 'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'middle', 'Color', app.Palette.muted, 'HitTest', 'off', 'Tag', 'placeholder');
    end
end
end
